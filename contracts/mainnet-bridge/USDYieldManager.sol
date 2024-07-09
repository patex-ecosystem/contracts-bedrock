// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldManager } from "./YieldManager.sol";
import { PatexPortal } from "../L1/PatexPortal.sol";
import { USDConversions } from "./USDConversions.sol";
import { Semver } from "../universal/Semver.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";

/// @custom:proxied
/// @title USDYieldManager
/// @notice Coordinates the accounting, asset management and
///         yield reporting from USD yield providers.
contract USDYieldManager is YieldManager, Semver {

    Postdeploys public postdeploys;

    /// @param _token Address of withdrawal token. It is assumed that the token
    ///               has 18 decimals.
    constructor(address _token) YieldManager(_token) Semver(1, 0, 0) {
        _disableInitializers();
    }

    /// @notice initializer
    /// @param _portal Address of the PatexPortal.
    /// @param _owner  Address of the YieldManager owner.
    function initialize(PatexPortal _portal, address _owner, Postdeploys _postdeploys) public initializer {
        postdeploys = _postdeploys;
        __YieldManager_init(_portal, _owner);
        if (TOKEN == address(USDConversions.DAI)) {
            USDConversions._init();
        }
    }

    /// @inheritdoc YieldManager
    function tokenBalance() public view override returns (uint256) {
        return IERC20(TOKEN).balanceOf(address(this));
    }

    /// @notice Wrapper for WithdrawalQueue._requestWithdrawal
    function requestWithdrawal(address recipient, uint256 amount)
        external
        onlyPatexBridge
        returns (uint256)
    {
        return _requestWithdrawal(address(recipient), amount);
    }

    /// @notice Wrapper for USDConversions._convertTo
    function convert(
        address inputTokenAddress,
        uint256 inputAmountWad,
        bytes memory _extraData
    ) external onlyPatexBridge returns (uint256) {
        return USDConversions._convertTo(
            inputTokenAddress,
            TOKEN,
            inputAmountWad,
            _extraData
        );
    }

    /// @notice Sends the yield report to the USDB contract.
    /// @param data Calldata to send in the message.
    function _reportYield(bytes memory data) internal override {
        portal.depositTransaction(Postdeploys(postdeploys).USDB(), 0, REPORT_YIELD_DEFAULT_GAS_LIMIT, false, data);
    }
}
