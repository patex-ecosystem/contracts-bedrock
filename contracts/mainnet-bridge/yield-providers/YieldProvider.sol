// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { YieldManager } from "../YieldManager.sol";
import { Semver } from "../../universal/Semver.sol";

/// @title YieldProvider
/// @notice Base contract for interacting and accounting for a
///         specific yield source.
abstract contract YieldProvider is Semver {
    YieldManager public immutable YIELD_MANAGER;

    uint256 public stakedPrincipal;
    uint256 public pendingBalance;

    event YieldCommit(bytes32 indexed provider, int256 yield);
    event Staked(bytes32 indexed provider, uint256 amount);
    event Unstaked(bytes32 indexed provider, uint256 amount);
    event Pending(bytes32 indexed provider, uint256 amount);
    event Claimed(bytes32 indexed provider, uint256 claimedAmount, uint256 expectedAmount);
    event InsurancePremiumPaid(bytes32 indexed provider, uint256 amount);
    event InsuranceWithdrawn(bytes32 indexed provider, uint256 amount);

    error InsufficientStakableFunds();
    error CallerIsNotYieldManager();
    error ContextIsNotYieldManager();
    error NotSupported();

    modifier onlyYieldManager() {
        if (msg.sender != address(YIELD_MANAGER)) {
            revert CallerIsNotYieldManager();
        }
        _;
    }

    modifier onlyDelegateCall() {
        if (address(this) != address(YIELD_MANAGER)) {
            revert ContextIsNotYieldManager();
        }
        _;
    }

    /// @param _yieldManager Address of the yield manager for the underlying
    ///        yield asset of this provider.
    constructor(YieldManager _yieldManager) Semver(1, 0, 0) {
        require(address(_yieldManager) != address(this));
        YIELD_MANAGER = _yieldManager;
    }

    /// @notice initialize
    function initialize() external onlyDelegateCall virtual {}

    function name() public pure virtual returns (string memory);

    function id() public view returns (bytes32) {
        return keccak256(abi.encodePacked(name(), version()));
    }

    /// @notice Whether staking is enabled for the given asset.
    function isStakingEnabled(address token) external view virtual returns (bool);

    /// @notice Current balance of the provider's staked funds.
    function stakedBalance() public view virtual returns (uint256);

    /// @notice Total value in the provider's yield method/protocol.
    function totalValue() public view returns (uint256) {
        return stakedBalance() + pendingBalance;
    }

    /// @notice Current amount of yield gained since the previous commit.
    function yield() public view virtual returns (int256);

    /// @notice Whether the provider supports yield insurance.
    function supportsInsurancePayment() public view virtual returns (bool) {
        return false;
    }

    /// @notice Gets insurance balance available for the provider's assets.
    function insuranceBalance() public view virtual returns (uint256) {
        revert("not supported");
    }

    /// @notice Commit the current amount of yield and checkpoint the accounting
    ///         variables.
    /// @return Amount of yield at this checkpoint.
    function commitYield() external onlyYieldManager returns (int256) {
        _beforeCommitYield();

        int256 _yield = yield();
        stakedPrincipal = stakedBalance();

        _afterCommitYield();

        emit YieldCommit(id(), _yield);
        return _yield;
    }

    /// @notice Stake YieldManager funds using the provider's yield method/protocol.
    ///         Must be called via `delegatecall` from the YieldManager.
    function stake(uint256) external virtual;

    /// @notice Unstake YieldManager funds from the provider's yield method/protocol.
    ///         Must be called via `delegatecall` from the YieldManager.
    /// @return pending Amount of funds pending in an unstaking delay
    /// @return claimed Amount of funds that have been claimed.
    ///         The yield provider is expected to return
    ///         (pending = 0, claimed = non-zero) if the funds are immediately
    ///         available for withdrawal, and (pending = non-zero, claimed = 0)
    ///         if the funds are in an unstaking delay.
    function unstake(uint256) external virtual returns (uint256 pending, uint256 claimed);

    /// @notice Pay insurance premium during a yield report. Must be called via
    ///         `delegatecall` from the YieldManager.
    function payInsurancePremium(uint256) external virtual onlyDelegateCall {
        revert NotSupported();
    }

    /// @notice Withdraw insurance funds to cover yield losses during a yield report.
    ///         Must be called via `delegatecall` from the YieldManager.
    function withdrawFromInsurance(uint256) external virtual onlyDelegateCall {
        revert NotSupported();
    }

    /// @notice Record a deposit to the stake balance of the provider to track the
    ///         principal balance.
    /// @param amount Amount of new staked balance to record.
    function recordStakedDeposit(uint256 amount) external virtual onlyYieldManager {
        stakedPrincipal += amount;
        emit Staked(id(), amount);
    }

    /// @notice Record a withdraw to the stake balance of the provider to track the
    ///         principal balance. This method should be called by the Yield Manager
    ///         after delegate-calling the provider's `unstake` method, which should
    ///         return the arguments to this method.
    function recordUnstaked(uint256 pending, uint256 claimed, uint256 expected) external virtual onlyYieldManager {
        _recordStakedWithdraw(expected);

        if (pending > 0) {
            require(claimed == 0 && pending == expected, "invalid yield provider implementation");
            _recordPending(pending);
        }

        if (claimed > 0) {
            require(pending == 0 && claimed == expected, "invalid yield provider implementation");
            _recordClaimed(claimed, expected);
        }
    }

    /// @notice A hook that is DELEGATE-CALLed by the Yield Manager for the provider
    ///         to perform any actions before the yield report process begins.
    function preCommitYieldReportDelegateCallHook() external virtual onlyDelegateCall {}

    /// @notice Record a withdraw the stake balance of the provider.
    /// @param amount Amount of staked balance to remove.
    function _recordStakedWithdraw(uint256 amount) internal virtual {
        stakedPrincipal -= amount;
        emit Unstaked(id(), amount);
    }

    /// @notice Record a pending balance to the provider. Needed only for providers
    ///         that use two-step withdrawals (e.g. Lido).
    function _recordPending(uint256 amount) internal virtual {
        pendingBalance += amount;
        emit Pending(id(), amount);
    }

    /// @notice Record a claimed balance to the provider. For providers with one-step
    ///         withdrawals, this method should be overriden to just emit the event
    ///         to avoid integer underflow.
    function _recordClaimed(uint256 claimed, uint256 expected) internal virtual {
        require(claimed <= expected, "invalid yield provider implementation");
        // Decrements pending balance by the expected amount, not the claimed amount.
        // If claimed < expected, the difference (expected - claimed) must be considered
        // as realized negative yield. To correctly reflect this, the difference is
        // subtracted from the pending balance (and totalProviderValue).
        pendingBalance -= expected;
        emit Claimed(id(), claimed, expected);
    }

    function _beforeCommitYield() internal virtual {}
    function _afterCommitYield() internal virtual {}
}
