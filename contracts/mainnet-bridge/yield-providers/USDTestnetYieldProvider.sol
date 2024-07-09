// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldManager } from "../YieldManager.sol";
import { YieldProvider } from "./YieldProvider.sol";
import { TestnetYieldProvider } from "./TestnetYieldProvider.sol";

contract USDTestnetYieldProvider is TestnetYieldProvider {
    constructor(
        YieldManager _yieldManager,
        address _owner,
        address _token
    ) TestnetYieldProvider(_yieldManager, _owner, _token) {}

    /// @inheritdoc YieldProvider
    function stake(uint256 amount) external override onlyDelegateCall {
        TOKEN.transfer(THIS, amount);
        stakedPrincipal += amount;
    }

    /// @inheritdoc YieldProvider
    function stakedBalance() public view override returns (uint256) {
        return TOKEN.balanceOf(address(YIELD_MANAGER));
    }

    function sendAsset(address recipient, uint256 amount) external override onlyYieldManager {
        TOKEN.transfer(recipient, amount);
    }

    function recordYield(int256 amount) external onlyOwner {
        if (amount > 0) {
            TOKEN.transferFrom(owner(), THIS, uint256(amount));
        } else {
            TOKEN.transfer(owner(), uint256(-1 * amount));
        }
    }
}
