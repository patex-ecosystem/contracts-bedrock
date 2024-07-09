// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { YieldManager } from "./YieldManager.sol";
import { PatexPortal } from "../L1/PatexPortal.sol";
import { Semver } from "../universal/Semver.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";

/// @custom:proxied
/// @title ETHYieldManager
/// @notice Coordinates the accounting, asset management and
///         yield reporting from ETH yield providers.
contract ETHYieldManager is YieldManager, Semver {
    error CallerIsNotPortal();

    Postdeploys public postdeploys;

    constructor() YieldManager(address(0)) Semver(1, 0, 0) {
        initialize(PatexPortal(payable(address(0))), address(0), Postdeploys(address(0)));
    }

    receive() external payable {}

    /// @notice initializer
    /// @param _portal Address of the PatexPortal.
    /// @param _owner  Address of the YieldManager owner.
    function initialize(PatexPortal _portal, address _owner, Postdeploys _postdeploys) public initializer {
        postdeploys = _postdeploys;
        __YieldManager_init(_portal, _owner);
    }

    /// @inheritdoc YieldManager
    function tokenBalance() public view override returns (uint256) {
        return address(this).balance;
    }

    /// @notice Wrapper for WithdrawalQueue._requestWithdrawal
    function requestWithdrawal(uint256 amount)
        external
        returns (uint256)
    {
        if (msg.sender != address(portal)) {
            revert CallerIsNotPortal();
        }
        return _requestWithdrawal(address(portal), amount);
    }

    /// @notice Sends the yield report to the Shares contract.
    /// @param data Calldata to send in the message.
    function _reportYield(bytes memory data) internal override {
        portal.depositTransaction(Postdeploys(postdeploys).SHARES(), 0, REPORT_YIELD_DEFAULT_GAS_LIMIT, false, data);
    }
}
