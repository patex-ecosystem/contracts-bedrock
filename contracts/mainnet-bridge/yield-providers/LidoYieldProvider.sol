// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldManager } from "../YieldManager.sol";
import { YieldProvider } from "./YieldProvider.sol";
import { WithdrawalQueue } from "../withdrawal-queue/WithdrawalQueue.sol";

interface ILido is IERC20 {
    function submit(address referral) external payable returns (uint256);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function isStakingPaused() external view returns (bool);
    function getPooledEthByShares(uint256 shares) external view returns (uint256);
}

interface IWithdrawalQueue {
    function getLastCheckpointIndex() external view returns (uint256);
    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex) external view returns (uint256[] memory hintIds);
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function getWithdrawalStatus(uint256[] calldata _requestIds) external view returns (WithdrawalRequestStatus[] memory statuses);
}

interface IInsurance {
    function coverLoss(address token, uint256 amount) external;
}

/// @notice output format struct for `_getWithdrawalStatus()` method
/// @dev taken from Lido's WithdrawalQueueBase contract
struct WithdrawalRequestStatus {
    /// @notice stETH token amount that was locked on withdrawal queue for this request
    uint256 amountOfStETH;
    /// @notice amount of stETH shares locked on withdrawal queue for this request
    uint256 amountOfShares;
    /// @notice address that can claim or transfer this request
    address owner;
    /// @notice timestamp of when the request was created, in seconds
    uint256 timestamp;
    /// @notice true, if request is finalized
    bool isFinalized;
    /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
    bool isClaimed;
}

/// @title LidoYieldProvider
/// @notice Provider for the Lido (ETH) yield source.
contract LidoYieldProvider is YieldProvider {
    // ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    // IWithdrawalQueue public constant WITHDRAWAL_QUEUE = IWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    ILido public constant LIDO = ILido(0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af);
    IWithdrawalQueue public constant WITHDRAWAL_QUEUE = IWithdrawalQueue(0x1583C7b3f4C3B008720E6BcE5726336b0aB25fdd);

    address public immutable THIS;
    uint256 public immutable claimBatchSize = 10;

    uint256[] public unstakeRequests;
    uint256 public lastClaimedIndex;

    /// @notice Emitted when a withdrawal is requested from Lido.
    /// @param requestId Lido WitdrawalQueue requestId.
    /// @param amount    Amount requested for withdrawal.
    event LidoUnstakeInitiated(uint256 indexed requestId, uint256 amount);

    /// @param _yieldManager Address of the yield manager for the underlying
    ///        yield asset of this provider.
    constructor(YieldManager _yieldManager) YieldProvider(_yieldManager) {
        THIS = address(this);
        // add a dummy request to make the index start from 1
        unstakeRequests.push(0);
    }

    /// @inheritdoc YieldProvider
    function initialize() external override onlyDelegateCall {
        LIDO.approve(address(WITHDRAWAL_QUEUE), type(uint256).max);
        LIDO.approve(address(YIELD_MANAGER), type(uint256).max);
    }

    /// @inheritdoc YieldProvider
    function name() public pure override returns (string memory) {
        return "LidoYieldProvider";
    }

    /// @inheritdoc YieldProvider
    function isStakingEnabled(address token) public view override returns (bool) {
        return token == address(LIDO) && !LIDO.isStakingPaused();
    }

    /// @inheritdoc YieldProvider
    function stakedBalance() public view override returns (uint256) {
        return LIDO.balanceOf(address(YIELD_MANAGER));
    }

    /// @inheritdoc YieldProvider
    function yield() public view override returns (int256) {
        return SafeCast.toInt256(stakedBalance()) - SafeCast.toInt256(stakedPrincipal);
    }

    /// @inheritdoc YieldProvider
    function supportsInsurancePayment() public view override returns (bool) {
        return YIELD_MANAGER.insurance() != address(0);
    }

    /// @inheritdoc YieldProvider
    function stake(uint256 amount) external override onlyDelegateCall {
        if (amount > YIELD_MANAGER.availableBalance()) {
            revert InsufficientStakableFunds();
        }
        LIDO.submit{value: amount}(address(0));
    }

    /// @inheritdoc YieldProvider
    function unstake(uint256 amount) external override onlyDelegateCall returns (uint256 pending, uint256 claimed) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256 requestId = WITHDRAWAL_QUEUE.requestWithdrawals(amounts, address(YIELD_MANAGER))[0];
        LidoYieldProvider(THIS).enqueueUnstakeRequest(requestId);
        emit LidoUnstakeInitiated(requestId, amount);

        pending = amount;
        claimed = 0;
    }

    function lastUnstakeRequestIndex() public view returns (uint256) {
        return unstakeRequests.length - 1;
    }

    function enqueueUnstakeRequest(uint256 lidoRequestId) external onlyYieldManager {
        unstakeRequests.push(lidoRequestId);
    }

    function setLastClaimedIndex(uint256 index) external onlyYieldManager {
        lastClaimedIndex = index;
    }

    function recordClaimed(uint256 claimed, uint256 expected) external onlyYieldManager {
        _recordClaimed(claimed, expected);
    }

    function preCommitYieldReportDelegateCallHook() external override onlyDelegateCall {
        _claim();
    }

    /// @inheritdoc YieldProvider
    function payInsurancePremium(uint256 amount) external override onlyDelegateCall {
        require(supportsInsurancePayment(), "insurance not supported");

        // send stETH to insurance
        LIDO.transfer(YIELD_MANAGER.insurance(), amount);
        // there is no need to update staked balance as insurance premium is expected
        // to come from the yield

        emit InsurancePremiumPaid(id(), amount);
    }

    /// @inheritdoc YieldProvider
    function withdrawFromInsurance(uint256 amount) external override onlyDelegateCall {
        require(supportsInsurancePayment(), "insurance not supported");
        IInsurance(YIELD_MANAGER.insurance()).coverLoss(address(LIDO), amount);

        emit InsuranceWithdrawn(id(), amount);
    }

    /// @inheritdoc YieldProvider
    function insuranceBalance() public view override returns (uint256) {
        return LIDO.balanceOf(YIELD_MANAGER.insurance());
    }

    /// @notice Claims withdrawals from Lido. It selects a batch of claimable
    ///         withdrawal requests (up to `claimBatchSize`), claims them and
    ///         records negative yield if any. This method is meant to be
    ///         delegate-called by the yield manager.
    function _claim() internal onlyDelegateCall returns (uint256 claimed, uint256 expected) {
        LidoYieldProvider yp = LidoYieldProvider(THIS);
        uint256 _lastClaimedIndex = yp.lastClaimedIndex();
        uint256 lastRequestIndex = yp.lastUnstakeRequestIndex();

        if (_lastClaimedIndex == lastRequestIndex) {
            // nothing to claim
            return (0, 0);
        }
        // sanity check
        require(_lastClaimedIndex < lastRequestIndex, "invalid claim index");

        // withdrawal status check for a batch of requests
        uint256 firstIndex = _lastClaimedIndex + 1;
        uint256 lastIndex = (lastRequestIndex - _lastClaimedIndex) > claimBatchSize
            ? firstIndex + claimBatchSize - 1
            : lastRequestIndex;

        uint256[] memory requestIds = new uint256[](lastIndex - firstIndex + 1);
        uint256 i;
        for (i = firstIndex; i <= lastIndex; i++) {
            requestIds[i - firstIndex] = yp.unstakeRequests(i);
        }

        WithdrawalRequestStatus[] memory statuses = WITHDRAWAL_QUEUE.getWithdrawalStatus(requestIds);

        for (i = 0; i < statuses.length; i++) {
            // find the first non-claimable request
            if (!(statuses[i].isFinalized && !statuses[i].isClaimed)) {
                break;
            }
            expected += statuses[i].amountOfStETH;
        }
        uint256 lastClaimableIndex = i + _lastClaimedIndex;
        // if there is nothing to claim, return
        if (lastClaimableIndex == _lastClaimedIndex) {
            return (0, 0);
        }

        uint256 balanceBefore = address(YIELD_MANAGER).balance;

        uint256[] memory claimableRequestIds = new uint256[](i);
        for (uint256 j = 0; j < i; j++) {
            claimableRequestIds[j] = requestIds[j];
        }

        uint256[] memory hintIds = WITHDRAWAL_QUEUE.findCheckpointHints(
            claimableRequestIds,
            1,
            WITHDRAWAL_QUEUE.getLastCheckpointIndex()
        );

        // update the last claimed index
        yp.setLastClaimedIndex(lastClaimableIndex);
        WITHDRAWAL_QUEUE.claimWithdrawals(claimableRequestIds, hintIds);

        claimed = address(YIELD_MANAGER).balance - balanceBefore;
        yp.recordClaimed(claimed, expected);
        uint256 negativeYield = expected - claimed;
        if (negativeYield > 0) {
            YIELD_MANAGER.recordNegativeYield(negativeYield);
        }
    }
}
