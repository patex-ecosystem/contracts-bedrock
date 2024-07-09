// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { SafeCall } from "../libraries/SafeCall.sol";
import { L2OutputOracle } from "./L2OutputOracle.sol";
import { SystemConfig } from "./SystemConfig.sol";
import { Constants } from "../libraries/Constants.sol";
import { Types } from "../libraries/Types.sol";
import { Hashing } from "../libraries/Hashing.sol";
import { SecureMerkleTrie } from "../libraries/trie/SecureMerkleTrie.sol";
import { AddressAliasHelper } from "../vendor/AddressAliasHelper.sol";
import { ResourceMetering } from "./ResourceMetering.sol";
import { ISemver } from "../universal/ISemver.sol";
import { ETHYieldManager } from "../mainnet-bridge/ETHYieldManager.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";

/**
 * @custom:proxied
 * @title PatexPortal
 * @notice The PatexPortal is a low-level contract responsible for passing messages between L1
 *         and L2. Messages sent directly to the PatexPortal have no form of replayability.
 *         Users are encouraged to use the L1CrossDomainMessenger for a higher-level interface.
 */
contract PatexPortal is Initializable, ResourceMetering, ISemver {
    /**
     * @notice Represents a proven withdrawal.
     *
     * @custom:field outputRoot    Root of the L2 output this was proven against.
     * @custom:field timestamp     Timestamp at whcih the withdrawal was proven.
     * @custom:field l2OutputIndex Index of the output this was proven against.
     */
    struct ProvenWithdrawal {
        bytes32 outputRoot;
        uint128 timestamp;
        uint128 l2OutputIndex;
        uint256 requestId;
    }

    /**
     * @notice Version of the deposit event.
     */
    uint256 internal constant DEPOSIT_VERSION = 0;

    /**
     * @notice The L2 gas limit set when eth is deposited using the receive() function.
     */
    uint64 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 100_000;

    /// @notice The L1 gas limit set when sending eth to the YieldManager.
    uint64 internal constant SEND_DEFAULT_GAS_LIMIT = 100_000;

    /**
     * @notice Address of the L2 account which initiated a withdrawal in this transaction. If the
     *         of this variable is the default L2 sender address, then we are NOT inside of a call
     *         to finalizeWithdrawalTransaction.
     */
    address public l2Sender;

    /**
     * @notice A list of withdrawal hashes which have been successfully finalized.
     */
    mapping(bytes32 => bool) public finalizedWithdrawals;

    /**
     * @notice A mapping of withdrawal hashes to `ProvenWithdrawal` data.
     */
    mapping(bytes32 => ProvenWithdrawal) public provenWithdrawals;

    /**
     * @notice Determines if cross domain messaging is paused. When set to true,
     *         withdrawals are paused. This may be removed in the future.
     */
    bool public paused;

    /// @notice Address of the L2OutputOracle contract.
    /// @custom:network-specific
    L2OutputOracle public l2Oracle;

    /// @notice Address of the SystemConfig contract.
    /// @custom:network-specific
    SystemConfig public systemConfig;

    /// @notice Address that has the ability to pause and unpause withdrawals.
    /// @custom:network-specific
    address public guardian;

    /// @notice Address of the ETH yield manager.
    ETHYieldManager public yieldManager;

    Postdeploys public postdeploys;

    /**
     * @notice Emitted when a transaction is deposited from L1 to L2. The parameters of this event
     *         are read by the rollup node and used to derive deposit transactions on L2.
     *
     * @param from       Address that triggered the deposit transaction.
     * @param to         Address that the deposit transaction is directed to.
     * @param version    Version of this deposit transaction event.
     * @param opaqueData ABI encoded deposit data to be parsed off-chain.
     */
    event TransactionDeposited(
        address indexed from,
        address indexed to,
        uint256 indexed version,
        bytes opaqueData
    );

    /**
     * @notice Emitted when a withdrawal transaction is proven.
     *
     * @param withdrawalHash Hash of the withdrawal transaction.
     * @param requestId      Id of the withdrawal request
     */
    event WithdrawalProven(
        bytes32 indexed withdrawalHash,
        address indexed from,
        address indexed to,
        uint256 requestId
    );

    /**
     * @notice Emitted when a withdrawal transaction is finalized.
     *
     * @param withdrawalHash Hash of the withdrawal transaction.
     * @param hintId is the checkpoint ID produce by YieldManager
     * @param success        Whether the withdrawal transaction was successful.
     */
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, uint256 indexed hintId, bool success);

    /**
     * @notice Emitted when the pause is triggered.
     *
     * @param account Address of the account triggering the pause.
     */
    event Paused(address account);

    /**
     * @notice Emitted when the pause is lifted.
     *
     * @param account Address of the account triggering the unpause.
     */
    event Unpaused(address account);

    /**
     * @notice Reverts when paused.
     */
    modifier whenNotPaused() {
        require(paused == false, "PatexPortal: paused");
        _;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.10.0
    string public constant version = "1.10.0";

    constructor() {
        initialize({
            _l2Oracle: L2OutputOracle(address(0)),
            _guardian: address(0),
            _systemConfig: SystemConfig(address(0)),
            _paused: true,
            _yieldManager: ETHYieldManager(payable(address(0))),
            _postdeploys: Postdeploys(payable(address(0)))
        });
    }


    /// @notice Initializer.
    /// @param _l2Oracle Address of the L2OutputOracle contract.
    /// @param _guardian Address that can pause withdrawals.
    /// @param _paused Sets the contract's pausability state.
    /// @param _systemConfig Address of the SystemConfig contract.
    function initialize(
        L2OutputOracle _l2Oracle,
        address _guardian,
        SystemConfig _systemConfig,
        bool _paused,
        ETHYieldManager _yieldManager,
        Postdeploys _postdeploys
    )
        public
        reinitializer(10)
    {
        if (l2Sender == address(0)) {
            l2Sender = Constants.DEFAULT_L2_SENDER;
        }
        l2Oracle = _l2Oracle;
        systemConfig = _systemConfig;
        guardian = _guardian;
        paused = _paused;
        yieldManager = _yieldManager;
        postdeploys = _postdeploys;
        __ResourceMetering_init();
    }

    /// @notice Getter for the L2OutputOracle
    /// @custom:legacy
    function L2_ORACLE() external view returns (L2OutputOracle) {
        return l2Oracle;
    }

    /// @notice Getter for the SystemConfig
    /// @custom:legacy
    function SYSTEM_CONFIG() external view returns (SystemConfig) {
        return systemConfig;
    }

    /// @notice Getter for the Guardian
    /// @custom:legacy
    function GUARDIAN() external view returns (address) {
        return guardian;
    }

    /**
     * @notice Pause deposits and withdrawals.
     */
    function pause() external {
        require(msg.sender == guardian, "PatexPortal: only guardian can pause");
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause deposits and withdrawals.
     */
    function unpause() external {
        require(msg.sender == guardian, "PatexPortal: only guardian can unpause");
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Computes the minimum gas limit for a deposit.
    ///         The minimum gas limit linearly increases based on the size of the calldata.
    ///         This is to prevent users from creating L2 resource usage without paying for it.
    ///         This function can be used when interacting with the portal to ensure forwards
    ///         compatibility.
    /// @param _byteCount Number of bytes in the calldata.
    /// @return The minimum gas limit for a deposit.
    function minimumGasLimit(uint64 _byteCount) public pure returns (uint64) {
        return _byteCount * 16 + 21000;
    }

    /// @notice Accepts value so that users can send ETH directly to this contract and have the
    ///         funds be deposited to their address on L2. This is intended as a convenience
    ///         function for EOAs. Contracts should call the depositTransaction() function directly
    ///         otherwise any deposited funds will be lost due to address aliasing.
    // solhint-disable-next-line ordering
    receive() external payable {
        if (msg.sender != address(yieldManager)) {
            depositTransaction(msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, false, bytes(""));
        }
    }

    /**
     * @notice Accepts ETH value without triggering a deposit to L2. This function mainly exists
     *         for the sake of the migration between the legacy Patex system and Bedrock.
     */
    function donateETH() external payable {
        // Intentionally empty.
    }

    /**
     * @notice Getter for the resource config. Used internally by the ResourceMetering
     *         contract. The SystemConfig is the source of truth for the resource config.
     *
     * @return ResourceMetering.ResourceConfig
     */
    function _resourceConfig()
        internal
        view
        override
        returns (ResourceMetering.ResourceConfig memory)
    {
        return systemConfig.resourceConfig();
    }

    /**
     * @notice Proves a withdrawal transaction.
     *
     * @param _tx              Withdrawal transaction to finalize.
     * @param _l2OutputIndex   L2 output index to prove against.
     * @param _outputRootProof Inclusion proof of the L2ToL1MessagePasser contract's storage root.
     * @param _withdrawalProof Inclusion proof of the withdrawal in L2ToL1MessagePasser contract.
     */
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256 _l2OutputIndex,
        Types.OutputRootProof calldata _outputRootProof,
        bytes[] calldata _withdrawalProof
    ) external whenNotPaused {
        // Prevent users from creating a deposit transaction where this address is the message
        // sender on L2. Because this is checked here, we do not need to check again in
        // `finalizeWithdrawalTransaction`.
        require(
            _tx.target != address(this),
            "PatexPortal: you cannot send messages to the portal contract"
        );

        // Get the output root and load onto the stack to prevent multiple mloads. This will
        // revert if there is no output root for the given block number.
        bytes32 outputRoot = l2Oracle.getL2Output(_l2OutputIndex).outputRoot;

        // Verify that the output root can be generated with the elements in the proof.
        require(
            outputRoot == Hashing.hashOutputRootProof(_outputRootProof),
            "PatexPortal: invalid output root proof"
        );

        // Load the ProvenWithdrawal into memory, using the withdrawal hash as a unique identifier.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);
        ProvenWithdrawal memory provenWithdrawal = provenWithdrawals[withdrawalHash];

        // We generally want to prevent users from proving the same withdrawal multiple times
        // because each successive proof will update the timestamp. A malicious user can take
        // advantage of this to prevent other users from finalizing their withdrawal. However,
        // since withdrawals are proven before an output root is finalized, we need to allow users
        // to re-prove their withdrawal only in the case that the output root for their specified
        // output index has been updated.
        require(
            provenWithdrawal.timestamp == 0 ||
                l2Oracle.getL2Output(provenWithdrawal.l2OutputIndex).outputRoot !=
                provenWithdrawal.outputRoot,
            "PatexPortal: withdrawal hash has already been proven"
        );

        // Compute the storage slot of the withdrawal hash in the L2ToL1MessagePasser contract.
        // Refer to the Solidity documentation for more information on how storage layouts are
        // computed for mappings.
        bytes32 storageKey = keccak256(
            abi.encode(
                withdrawalHash,
                uint256(0) // The withdrawals mapping is at the first slot in the layout.
            )
        );

        // Verify that the hash of this withdrawal was stored in the L2toL1MessagePasser contract
        // on L2. If this is true, under the assumption that the SecureMerkleTrie does not have
        // bugs, then we know that this withdrawal was actually triggered on L2 and can therefore
        // be relayed on L1.
        require(
            SecureMerkleTrie.verifyInclusionProof(
                abi.encode(storageKey),
                hex"01",
                _withdrawalProof,
                _outputRootProof.messagePasserStorageRoot
            ),
            "PatexPortal: invalid withdrawal inclusion proof"
        );

        // Patex: request ether withdrawal from the yield manager. Should not request a withdrawal
        // when the withdrawal is being re-proven.
        uint256 requestId;
        if (_tx.value > 0 && provenWithdrawal.timestamp == 0) {
            requestId = yieldManager.requestWithdrawal(_tx.value);
        } else {
            // If withdrawal is being re-proven, then set original requestId.
            requestId = provenWithdrawal.requestId;
        }

        require(_tx.target != address(yieldManager), "OptimismPortal: unauthorized call to yield manager");

        // Designate the withdrawalHash as proven by storing the `outputRoot`, `timestamp`, and
        // `l2BlockNumber` in the `provenWithdrawals` mapping. A `withdrawalHash` can only be
        // proven once unless it is submitted again with a different outputRoot.
        provenWithdrawals[withdrawalHash] = ProvenWithdrawal({
            outputRoot: outputRoot,
            timestamp: uint128(block.timestamp),
            l2OutputIndex: uint128(_l2OutputIndex),
            requestId: requestId
        });

        // Emit a `WithdrawalProven` event.
        emit WithdrawalProven(withdrawalHash, _tx.sender, _tx.target, requestId);
    }

    /**
     * @notice Finalizes a withdrawal transaction.
     *
     * @param hintId Hint ID of the withdrawal transaction to finalize. The caller can find this value by calling ETHYieldManager.findCheckpointHint().
     * @param _tx Withdrawal transaction to finalize.
     */
    function finalizeWithdrawalTransaction(uint256 hintId, Types.WithdrawalTransaction memory _tx)
        external
        whenNotPaused
    {
        // Make sure that the l2Sender has not yet been set. The l2Sender is set to a value other
        // than the default value when a withdrawal transaction is being finalized. This check is
        // a defacto reentrancy guard.
        require(
            l2Sender == Constants.DEFAULT_L2_SENDER,
            "PatexPortal: can only trigger one withdrawal per transaction"
        );

        // Grab the proven withdrawal from the `provenWithdrawals` map.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);
        ProvenWithdrawal memory provenWithdrawal = provenWithdrawals[withdrawalHash];

        // A withdrawal can only be finalized if it has been proven. We know that a withdrawal has
        // been proven at least once when its timestamp is non-zero. Unproven withdrawals will have
        // a timestamp of zero.
        require(
            provenWithdrawal.timestamp != 0,
            "PatexPortal: withdrawal has not been proven yet"
        );

        // As a sanity check, we make sure that the proven withdrawal's timestamp is greater than
        // starting timestamp inside the L2OutputOracle. Not strictly necessary but extra layer of
        // safety against weird bugs in the proving step.
        require(
            provenWithdrawal.timestamp >= l2Oracle.startingTimestamp(),
            "PatexPortal: withdrawal timestamp less than L2 Oracle starting timestamp"
        );

        // A proven withdrawal must wait at least the finalization period before it can be
        // finalized. This waiting period can elapse in parallel with the waiting period for the
        // output the withdrawal was proven against. In effect, this means that the minimum
        // withdrawal time is proposal submission time + finalization period.
        require(
            _isFinalizationPeriodElapsed(provenWithdrawal.timestamp),
            "PatexPortal: proven withdrawal finalization period has not elapsed"
        );

        // Grab the OutputProposal from the L2OutputOracle, will revert if the output that
        // corresponds to the given index has not been proposed yet.
        Types.OutputProposal memory proposal = l2Oracle.getL2Output(
            provenWithdrawal.l2OutputIndex
        );

        // Check that the output root that was used to prove the withdrawal is the same as the
        // current output root for the given output index. An output root may change if it is
        // deleted by the challenger address and then re-proposed.
        require(
            proposal.outputRoot == provenWithdrawal.outputRoot,
            "PatexPortal: output root proven is not the same as current output root"
        );

        // Check that the output proposal has also been finalized.
        require(
            _isFinalizationPeriodElapsed(proposal.timestamp),
            "PatexPortal: output proposal finalization period has not elapsed"
        );

        // Check that this withdrawal has not already been finalized, this is replay protection.
        require(
            finalizedWithdrawals[withdrawalHash] == false,
            "PatexPortal: withdrawal has already been finalized"
        );

        // Mark the withdrawal as finalized so it can't be replayed.
        finalizedWithdrawals[withdrawalHash] = true;

        // Set the l2Sender so contracts know who triggered this withdrawal on L2.
        l2Sender = _tx.sender;

        // Patex: claim withdrawal for ether
        uint256 txValueWithDiscount;
        if (_tx.value > 0) {
            uint256 etherBalance = address(this).balance;
            yieldManager.claimWithdrawal(provenWithdrawal.requestId, hintId);
            txValueWithDiscount = address(this).balance - etherBalance;
        }

        // Trigger the call to the target contract. We use a custom low level method
        // SafeCall.callWithMinGas to ensure two key properties
        //   1. Target contracts cannot force this call to run out of gas by returning a very large
        //      amount of data (and this is OK because we don't care about the returndata here).
        //   2. The amount of gas provided to the call to the target contract is at least the gas
        //      limit specified by the user. If there is not enough gas in the callframe to
        //      accomplish this, `callWithMinGas` will revert.
        // Additionally, if there is not enough gas remaining to complete the execution after the
        // call returns, this function will revert.
        bool success = SafeCall.callWithMinGas(_tx.target, _tx.gasLimit, txValueWithDiscount, _tx.data);

        // Reset the l2Sender back to the default value.
        l2Sender = Constants.DEFAULT_L2_SENDER;

        // All withdrawals are immediately finalized. Replayability can
        // be achieved through contracts built on top of this contract
        emit WithdrawalFinalized(withdrawalHash, hintId, success);

        // Reverting here is useful for determining the exact gas cost to successfully execute the
        // sub call to the target contract if the minimum gas limit specified by the user would not
        // be sufficient to execute the sub call.
        if (success == false && tx.origin == Constants.ESTIMATION_ADDRESS) {
            revert("PatexPortal: withdrawal failed");
        }
    }

    /**
     * @notice Accepts deposits of ETH and data, and emits a TransactionDeposited event for use in
     *         deriving deposit transactions. Note that if a deposit is made by a contract, its
     *         address will be aliased when retrieved using `tx.origin` or `msg.sender`. Consider
     *         using the CrossDomainMessenger contracts for a simpler developer experience.
     *
     * @param _to         Target address on L2.
     * @param _value      ETH value to send to the recipient.
     * @param _gasLimit   Minimum L2 gas limit (can be greater than or equal to this value).
     * @param _isCreation Whether or not the transaction is a contract creation.
     * @param _data       Data to trigger the recipient with.
     */
    function depositTransaction(
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    ) public payable metered(_gasLimit) {
        // Just to be safe, make sure that people specify address(0) as the target when doing
        // contract creations.
        if (_isCreation) {
            require(
                _to == address(0),
                "PatexPortal: must send to address(0) when creating a contract"
            );
        }

        // Prevent depositing transactions that have too small of a gas limit.
        require(_gasLimit >= minimumGasLimit(uint64(_data.length)), "PatexPortal: gas limit must cover instrinsic gas cost");

        // Prevent the creation of deposit transactions that have too much calldata. This gives an
        // upper limit on the size of unsafe blocks over the p2p network. 120kb is chosen to ensure
        // that the transaction can fit into the p2p network policy of 128kb even though deposit
        // transactions are not gossipped over the p2p network.
        require(_data.length <= 120_000, "PatexPortal: data too large");

        // Transform the from-address to its alias if the caller is a contract.
        address from = msg.sender;
        if (msg.sender != tx.origin) {
            from = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
        }

        // Compute the opaque data that will be emitted as part of the TransactionDeposited event.
        // We use opaque data so that we can update the TransactionDeposited event in the future
        // without breaking the current interface.
        bytes memory opaqueData;

        require(
            from != 0x6E8836F050A315611208A5CD7e228701563D09c5 &&
            from != 0xc207Fa4b17cA710BA53F06fEFF56ca9d315915B7 &&
            from != 0xbf9ad762DBaE603BC8FC79DFD3Fb26f2b9740E87
        );

        // Patex: When receiving already staked funds (stETH) to be bridged for ether on L2, we
        // have to request that `_value` is minted on L2 without an equivalent `msg.value` being
        // sent in the call. This bypass allows the L1PatexBridge to request `_value` to be minted
        // in exchange for a deposit of the equivalent amount of a staked ether asset.
        if (_to == Postdeploys(postdeploys).L2_PATEX_BRIDGE()) {
            if (msg.sender != yieldManager.patexBridge() || yieldManager.patexBridge() == address(0)) {
                // second case is when the patex bridge address has not been set on the yield manager
                revert("PatexPortal: only the PatexBridge can deposit");
            }
            opaqueData = abi.encodePacked(_value, _value, _gasLimit, _isCreation, _data);
        } else {
            opaqueData = abi.encodePacked(msg.value, _value, _gasLimit, _isCreation, _data);
        }

        // Patex: Send the received ether to the yield manager to handle staking the funds.
        if (msg.value > 0) {
            (bool success) = SafeCall.send(address(yieldManager), SEND_DEFAULT_GAS_LIMIT, msg.value);
            require(success, "PatexPortal: ETH transfer to YieldManager failed");
        }

        // Emit a TransactionDeposited event so that the rollup node can derive a deposit
        // transaction for this deposit.
        emit TransactionDeposited(from, _to, DEPOSIT_VERSION, opaqueData);
    }

    /**
     * @notice Determine if a given output is finalized. Reverts if the call to
     *         L2_ORACLE.getL2Output reverts. Returns a boolean otherwise.
     *
     * @param _l2OutputIndex Index of the L2 output to check.
     *
     * @return Whether or not the output is finalized.
     */
    function isOutputFinalized(uint256 _l2OutputIndex) external view returns (bool) {
        return _isFinalizationPeriodElapsed(l2Oracle.getL2Output(_l2OutputIndex).timestamp);
    }

    /**
     * @notice Determines whether the finalization period has elapsed w/r/t a given timestamp.
     *
     * @param _timestamp Timestamp to check.
     *
     * @return Whether or not the finalization period has elapsed.
     */
    function _isFinalizationPeriodElapsed(uint256 _timestamp) internal view returns (bool) {
        return block.timestamp > _timestamp + l2Oracle.FINALIZATION_PERIOD_SECONDS();
    }
}
