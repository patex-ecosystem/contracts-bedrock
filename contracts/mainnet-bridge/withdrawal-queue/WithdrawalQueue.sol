// SPDX-FileCopyrightText: 2023 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.15;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Initializable } from "../../openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeCall } from "../../libraries/SafeCall.sol";

/// @title WithdrawalQueue
/// @notice Queue for storing and managing withdrawal requests.
///         This contract is based on Lido's WithdrawalQueue and has been
///         modified to support Patex specific logic such as withdrawal discounts.
contract WithdrawalQueue is Initializable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    /// @notice The L1 gas limit set when sending eth to the YieldManager.
    uint256 internal constant SEND_DEFAULT_GAS_LIMIT = 100_000;

    /// @notice precision base for share rate
    uint256 internal constant E27_PRECISION_BASE = 1e27;

    /// @notice return value for the `find...` methods in case of no result
    uint256 internal constant NOT_FOUND = 0;

    address public immutable TOKEN;

    WithdrawalRequest[] private _requests;
    mapping(address => EnumerableSet.UintSet) private _requestsByOwner;
    Checkpoint[] private _checkpoints;
    uint256 private lastRequestId;
    uint256 private lastFinalizedRequestId;
    uint256 private lastCheckpointId;
    uint256 private lockedBalance;

    /// @notice Reserve extra slots (to a total of 50) in the storage layout for future upgrades.
    ///         A gap size of 42 was chosen here, so that the first slot used in a child contract
    ///         would be a multiple of 50.
    uint256[42] private __gap;

    /// @notice structure representing a request for withdrawal
    struct WithdrawalRequest {
        /// @notice sum of the all tokens submitted for withdrawals including this request (nominal amount)
        uint128 cumulativeAmount;
        /// @notice address that can claim the request and receives the funds
        address recipient;
        /// @notice block.timestamp when the request was created
        uint40 timestamp;
        /// @notice flag if the request was claimed
        bool claimed;
    }

    /// @notice output format struct for `_getWithdrawalStatus()` method
    struct WithdrawalRequestStatus {
        /// @notice nominal token amount that was locked on withdrawal queue for this request
        uint256 amount;
        /// @notice address that can claim or transfer this request
        address recipient;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    /// @notice structure to store discounts for requests that are affected by negative rebase
    /// All requests covered by the checkpoint are affected by the same discount rate `sharePrice`.
    struct Checkpoint {
        uint256 fromRequestId;
        uint256 sharePrice;
    }

    /// @dev amount represents the nominal amount of tokens that were withdrawn (burned) on L2.
    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed requestor,
        address indexed recipient,
        uint256 amount
    );

    /// @dev amountOfETHLocked represents the real amount of ETH that was locked in the queue and will be
    ///      transferred to the recipient on claim.
    event WithdrawalsFinalized(
        uint256 indexed from,
        uint256 indexed to,
        uint256 indexed checkpointId,
        uint256 amountOfETHLocked,
        uint256 timestamp,
        uint256 sharePrice
    );

    /// @dev amount represents the real amount of ETH that was transferred to the recipient.
    event WithdrawalClaimed(
        uint256 indexed requestId, address indexed recipient, uint256 amountOfETH
    );

    error InvalidRequestId(uint256 _requestId);
    error InvalidRequestIdRange(uint256 startId, uint256 endId);
    error InvalidSharePrice();
    error RequestNotFoundOrNotFinalized(uint256 _requestId);
    error RequestAlreadyClaimed(uint256 _requestId);
    error InvalidHint(uint256 _hint);
    error RequestIdsNotSorted();
    error CallerIsNotRecipient();
    error WithdrawalTransferFailed();
    error InsufficientBalance();

    constructor(address _token) {
        TOKEN = _token;
    }

    /// @notice initialize the contract with the dummy request and checkpoint
    ///         as the zero elements of the corresponding arrays so that
    ///         the first element of the array has index 1
    function __WithdrawalQueue_init() internal onlyInitializing {
        _requests.push(WithdrawalRequest(0, address(0), uint40(block.timestamp), true));
        _checkpoints.push(Checkpoint(0, 0));
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            statuses[i] = _getStatus(_requestIds[i]);
        }
    }

    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestIds) {
        return _requestsByOwner[_owner].values();
    }

    function getClaimableEther(uint256[] calldata _requestIds, uint256[] calldata _hintIds)
        external
        view
        returns (uint256[] memory claimableEthValues)
    {
        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimableEthValues[i] = _getClaimableEther(_requestIds[i], _hintIds[i]);
        }
    }

    function _getClaimableEther(uint256 _requestId, uint256 _hintId) internal view returns (uint256) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        if (_requestId > lastFinalizedRequestId) return 0;

        WithdrawalRequest storage request = _requests[_requestId];
        if (request.claimed) return 0;

        return _calculateClaimableEther(_requestId, _hintId);
    }

    /// @notice id of the last request
    ///  NB! requests are indexed from 1, so it returns 0 if there is no requests in the queue
    function getLastRequestId() external view returns (uint256) {
        return lastRequestId;
    }

    /// @notice id of the last finalized request
    ///  NB! requests are indexed from 1, so it returns 0 if there is no finalized requests in the queue
    function getLastFinalizedRequestId() external view returns (uint256) {
        return lastFinalizedRequestId;
    }

    /// @notice amount of ETH on this contract balance that is locked for withdrawal and available to claim
    ///  NB! this is the real amount of ETH (i.e. sum of (nominal amount of ETH burned on L2 * sharePrice))
    function getLockedBalance() public view returns (uint256) {
        return lockedBalance;
    }

    /// @notice return the last checkpoint id in the queue
    function getLastCheckpointId() external view returns (uint256) {
        return lastCheckpointId;
    }

    /// @notice return the number of unfinalized requests in the queue
    function unfinalizedRequestNumber() public view returns (uint256) {
        return lastRequestId - lastFinalizedRequestId;
    }

    /// @notice Returns the amount of ETH in the queue yet to be finalized
    ///  NB! this is the nominal amount of ETH burned on L2
    function unfinalizedAmount() internal view returns (uint256) {
        return
            _requests[lastRequestId].cumulativeAmount - _requests[lastFinalizedRequestId].cumulativeAmount;
    }

    /// @dev Finalize requests in the queue
    /// @notice sharePrice has 1e27 precision
    ///  Emits WithdrawalsFinalized event.
    function _finalize(
        uint256 _lastRequestIdToBeFinalized,
        uint256 availableBalance,
        uint256 sharePrice
    ) internal returns (uint256 nominalAmountToFinalize, uint256 realAmountToFinalize, uint256 checkpointId) {
        // share price cannot be larger than 1e27
        if (sharePrice > E27_PRECISION_BASE) {
            revert InvalidSharePrice();
        }

        if (_lastRequestIdToBeFinalized != 0) {
            if (_lastRequestIdToBeFinalized > lastRequestId) revert InvalidRequestId(_lastRequestIdToBeFinalized);
            uint256 _lastFinalizedRequestId = lastFinalizedRequestId;
            if (_lastRequestIdToBeFinalized <= _lastFinalizedRequestId) revert InvalidRequestId(_lastRequestIdToBeFinalized);

            WithdrawalRequest memory lastFinalizedRequest = _requests[_lastFinalizedRequestId];
            WithdrawalRequest memory requestToFinalize = _requests[_lastRequestIdToBeFinalized];

            nominalAmountToFinalize = requestToFinalize.cumulativeAmount - lastFinalizedRequest.cumulativeAmount;
            realAmountToFinalize = (nominalAmountToFinalize * sharePrice) / E27_PRECISION_BASE;
            if (realAmountToFinalize > availableBalance) {
                revert InsufficientBalance();
            }

            uint256 firstRequestIdToFinalize = _lastFinalizedRequestId + 1;

            lockedBalance += realAmountToFinalize;
            lastFinalizedRequestId = _lastRequestIdToBeFinalized;

            checkpointId = _createCheckpoint(firstRequestIdToFinalize, sharePrice);

            emit WithdrawalsFinalized(
                firstRequestIdToFinalize,
                _lastRequestIdToBeFinalized,
                checkpointId,
                realAmountToFinalize,
                block.timestamp,
                sharePrice
            );
        }
    }

    /// @notice Finds the list of hints for the given `_requestIds` searching among the checkpoints with indices
    ///  in the range  `[_firstIndex, _lastIndex]`.
    ///  NB! Array of request ids should be sorted
    ///  NB! `_firstIndex` should be greater than 0, because checkpoint list is 1-based array
    ///  Usage: findCheckpointHints(_requestIds, 1, getLastCheckpointIndex())
    /// @param _requestIds ids of the requests sorted in the ascending order to get hints for
    /// @param _firstIndex left boundary of the search range. Should be greater than 0
    /// @param _lastIndex right boundary of the search range. Should be less than or equal to getLastCheckpointIndex()
    /// @return hintIds array of hints used to find required checkpoint for the request
    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds)
    {
        hintIds = new uint256[](_requestIds.length);
        uint256 prevRequestId = 0;
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            if (_requestIds[i] < prevRequestId) {
                revert RequestIdsNotSorted();
            }
            hintIds[i] = findCheckpointHint(_requestIds[i], _firstIndex, _lastIndex);
            _firstIndex = hintIds[i];
            prevRequestId = _requestIds[i];
        }
    }

    /// @dev View function to find a checkpoint hint to use in `claimWithdrawal()` and `getClaimableEther()`
    ///  Search will be performed in the range of `[_firstIndex, _lastIndex]`
    ///
    /// @param _requestId request id to search the checkpoint for
    /// @param _start index of the left boundary of the search range, should be greater than 0
    /// @param _end index of the right boundary of the search range, should be less than or equal
    ///  to queue.lastCheckpointId
    ///
    /// @return hint for later use in other methods or 0 if hint not found in the range
    function findCheckpointHint(uint256 _requestId, uint256 _start, uint256 _end) public view returns (uint256) {
        if (_requestId == 0 || _requestId > lastRequestId) {
            revert InvalidRequestId(_requestId);
        }

        uint256 lastCheckpointIndex = lastCheckpointId;
        if (_start == 0 || _end > lastCheckpointIndex) {
            revert InvalidRequestIdRange(_start, _end);
        }

        if (lastCheckpointIndex == 0 || _requestId > lastFinalizedRequestId || _start > _end) {
            return NOT_FOUND;
        }

        // Right boundary
        if (_requestId >= _checkpoints[_end].fromRequestId) {
            // it's the last checkpoint, so it's valid
            if (_end == lastCheckpointIndex) {
                return _end;
            }
            // it fits right before the next checkpoint
            if (_requestId < _checkpoints[_end + 1].fromRequestId) {
                return _end;
            }

            return NOT_FOUND;
        }
        // Left boundary
        if (_requestId < _checkpoints[_start].fromRequestId) {
            return NOT_FOUND;
        }

        // Binary search
        uint256 min = _start;
        uint256 max = _end - 1;

        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (_checkpoints[mid].fromRequestId <= _requestId) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /// @dev Returns the status of the withdrawal request with `_requestId` id
    function _getStatus(uint256 _requestId) internal view returns (WithdrawalRequestStatus memory status) {
        if (_requestId == 0 || _requestId > lastRequestId) revert InvalidRequestId(_requestId);

        WithdrawalRequest memory request = _requests[_requestId];
        WithdrawalRequest memory previousRequest = _requests[_requestId - 1];

        status = WithdrawalRequestStatus(
            request.cumulativeAmount - previousRequest.cumulativeAmount,
            request.recipient,
            request.timestamp,
            _requestId <= lastFinalizedRequestId,
            request.claimed
        );
    }

    /// @dev creates a new `WithdrawalRequest` in the queue
    ///  Emits WithdrawalRequested event
    function _requestWithdrawal(address recipient, uint256 amount)
        internal
        returns (uint256 requestId)
    {
        uint256 _lastRequestId = lastRequestId;
        WithdrawalRequest memory lastRequest = _requests[_lastRequestId];

        uint128 cumulativeAmount = lastRequest.cumulativeAmount + SafeCast.toUint128(amount);

        requestId = _lastRequestId + 1;

        lastRequestId = requestId;

        WithdrawalRequest memory newRequest = WithdrawalRequest(
            cumulativeAmount,
            recipient,
            uint40(block.timestamp),
            false
        );
        _requests.push(newRequest);
        _requestsByOwner[recipient].add(requestId);

        emit WithdrawalRequested(requestId, msg.sender, recipient, amount);
    }

    /// @dev assumes firstRequestIdToFinalize > _lastFinalizedRequestId && sharePrice <= 1e27
    function _createCheckpoint(uint256 firstRequestIdToFinalize, uint256 sharePrice) internal returns (uint256) {
        _checkpoints.push(Checkpoint(firstRequestIdToFinalize, sharePrice));
        lastCheckpointId += 1;
        return lastCheckpointId;
    }

    /// @dev can only be called by request.recipient (YieldManager)
    function claimWithdrawal(uint256 _requestId, uint256 _hintId) external returns (bool success) {
        if (_requestId == 0) revert InvalidRequestId(_requestId);
        if (_requestId > lastFinalizedRequestId) revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = _requests[_requestId];

        if (request.claimed) revert RequestAlreadyClaimed(_requestId);
        request.claimed = true;

        address recipient = request.recipient;
        if (msg.sender != recipient) {
            revert CallerIsNotRecipient();
        }

        uint256 realAmount = _calculateClaimableEther(_requestId, _hintId);
        lockedBalance -= realAmount;

        if (TOKEN == address(0)) {
            (success) = SafeCall.send(recipient, SEND_DEFAULT_GAS_LIMIT, realAmount);
        } else {
            IERC20(TOKEN).safeTransfer(recipient, realAmount);
            success = true;
        }

        if (!success) {
            revert WithdrawalTransferFailed();
        }

        emit WithdrawalClaimed(_requestId, recipient, realAmount);
    }

    /// @dev Calculate the amount of ETH that can be claimed for the withdrawal request with `_requestId`.
    ///  NB! This function returns the real amount of ETH that can be claimed by the recipient, not the nominal amount
    ///  that was burned on L2. The real amount is calculated as nominal amount * share price, which can be found
    ///  in the checkpoint with `_hintId`.
    function _calculateClaimableEther(uint256 _requestId, uint256 _hintId)
        internal
        view
        returns (uint256)
    {
        if (_hintId == 0) {
            revert InvalidHint(_hintId);
        }

        uint256 lastCheckpointIndex = lastCheckpointId;
        if (_hintId > lastCheckpointIndex) {
            revert InvalidHint(_hintId);
        }

        Checkpoint memory checkpoint = _checkpoints[_hintId];
        if (_requestId < checkpoint.fromRequestId) {
            revert InvalidHint(_hintId);
        }
        if (_hintId < lastCheckpointIndex) {
            Checkpoint memory nextCheckpoint = _checkpoints[_hintId + 1];
            if (_requestId >= nextCheckpoint.fromRequestId) {
                revert InvalidHint(_hintId);
            }
        }

        WithdrawalRequest storage prevRequest = _requests[_requestId - 1];
        WithdrawalRequest storage request = _requests[_requestId];

        uint256 nominalAmount = request.cumulativeAmount - prevRequest.cumulativeAmount;
        return (nominalAmount * checkpoint.sharePrice) / E27_PRECISION_BASE;
    }
}
