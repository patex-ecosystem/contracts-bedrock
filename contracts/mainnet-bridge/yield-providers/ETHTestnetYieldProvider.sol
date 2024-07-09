// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldManager } from "../YieldManager.sol";
import { YieldProvider } from "./YieldProvider.sol";
import { TestnetYieldProvider } from "./TestnetYieldProvider.sol";

contract ETHTestnetYieldProvider is TestnetYieldProvider {
    constructor(
        YieldManager _yieldManager,
        address _owner,
        address _token
    ) TestnetYieldProvider(_yieldManager, _owner, _token) {}

    /// @inheritdoc YieldProvider
    function stake(uint256 amount) external override onlyDelegateCall {
        (bool success,) = THIS.call{value: amount}("");
        require(success);
        stakedPrincipal += amount;
    }

    /// @inheritdoc YieldProvider
    function stakedBalance() public view override returns (uint256) {
        return address(this).balance;
    }

    function sendAsset(address recipient, uint256 amount) external override onlyYieldManager {
        (bool success,) = recipient.call{value: amount}("");
        require(success);
    }

    function recordYield(int256 amount) external payable onlyOwner {
        if (amount > 0) {
            require(msg.value == uint256(amount));
        } else {
            (bool success,) = owner().call{value: uint256(-1 * amount)}("");
            require(success);
        }
    }
}
