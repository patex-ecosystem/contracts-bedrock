// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Postdeploys is Ownable {
    /// @notice Address of the Shares predeploy.
    address public SHARES = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the Gas predeploy.
    address public GAS = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the Patex predeploy.
    address public PATEX = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the USDB predeploy.
    address public USDB = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the WETH predeploy.
    address public WETH_REBASING = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the L2PatexBridge predeploy.
    address public L2_PATEX_BRIDGE = 0x0000000000000000000000000000000000000000;

    function setSHARES(address _SHARES) public onlyOwner {
        SHARES = _SHARES;
    }

    function setGAS(address _GAS) public onlyOwner {
        GAS = _GAS;
    }

    function setPATEX(address _PATEX) public onlyOwner {
        PATEX = _PATEX;
    }

    function setUSDB(address _USDB) public onlyOwner {
        USDB = _USDB;
    }

    function setWETH_REBASING(address _WETH_REBASING) public onlyOwner {
        WETH_REBASING = _WETH_REBASING;
    }

    function setL2_PATEX_BRIDGE(address _L2_PATEX_BRIDGE) public onlyOwner {
        L2_PATEX_BRIDGE = _L2_PATEX_BRIDGE;
    }
}
