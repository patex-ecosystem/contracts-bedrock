// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldManager } from "../YieldManager.sol";
import { YieldProvider } from "./YieldProvider.sol";

interface IInsurance {
    function coverLoss(address token, uint256 amount) external;
}

/// @title TestnetYieldProvider
/// @notice Provider for simulating a yield source on testnet.
abstract contract TestnetYieldProvider is YieldProvider, Ownable {
    IERC20 immutable TOKEN;
    address immutable THIS;

    /// @param _yieldManager Address of the yield manager for the underlying
    ///        yield asset of this provider.
    constructor(YieldManager _yieldManager, address _owner, address _token) YieldProvider(_yieldManager) {
        _transferOwnership(_owner);
        TOKEN = IERC20(_token);
        THIS = address(this);
    }

    /// @inheritdoc YieldProvider
    function initialize() external override onlyDelegateCall {}

    /// @inheritdoc YieldProvider
    function name() public pure override returns (string memory) {
        return "TestnetYieldProvider";
    }

    /// @inheritdoc YieldProvider
    function isStakingEnabled(address token) public view override returns (bool) {
        return token == address(TOKEN);
    }

    /// @inheritdoc YieldProvider
    function yield() public view override returns (int256) {
        return SafeCast.toInt256(stakedBalance()) - SafeCast.toInt256(stakedPrincipal);
    }

    /// @inheritdoc YieldProvider
    function supportsInsurancePayment() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc YieldProvider
    function unstake(uint256 amount) external override onlyDelegateCall returns (uint256, uint256) {
        TestnetYieldProvider(THIS).sendAsset(address(YIELD_MANAGER), amount);
        return (0, amount);
    }

    /// @inheritdoc YieldProvider
    function payInsurancePremium(uint256 amount) external override onlyDelegateCall {
        TestnetYieldProvider(THIS).sendAsset(address(YIELD_MANAGER.insurance()), amount);
    }

    /// @notice Withdraw insurance funds to cover yield losses during a yield report.
    ///         Must be called via `delegatecall` from the YieldManager.
    function withdrawFromInsurance(uint256 amount) external override onlyDelegateCall {
        require(supportsInsurancePayment(), "insurance not supported");
        IInsurance(YIELD_MANAGER.insurance()).coverLoss(address(TOKEN), amount);
    }

    function sendAsset(address recipient, uint256 amount) external virtual;
}
