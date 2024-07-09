// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Initializable } from "../openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldManager } from "./YieldManager.sol";
import { Semver } from "./YieldManager.sol";

/// @custom:proxied
/// @title Insurance
/// @notice Holds the yield insurance funds and allows yield managers to
///         withdraw to cover losses.
contract Insurance is Initializable, Semver {
    using SafeERC20 for IERC20;

    address public admin;
    YieldManager immutable YIELD_MANAGER;

    error OnlyAdmin();
    error OnlyAdminOrYieldManager();
    error InsufficientBalance();
    error CannotSetAdminAsZeroAddress();

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert OnlyAdmin();
        }
        _;
    }

    modifier onlyAdminOrYieldManager() {
        if (msg.sender != admin && msg.sender != address(YIELD_MANAGER)) {
            revert OnlyAdminOrYieldManager();
        }
        _;
    }

    constructor(YieldManager _yieldManager) Semver(1, 0, 0) {
        YIELD_MANAGER = _yieldManager;
        initialize(address(0));
    }

    function initialize(address _admin) public initializer {
        admin = _admin;
    }

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) {
            revert CannotSetAdminAsZeroAddress();
        }
        admin = _admin;
    }

    function coverLoss(address token, uint256 amount) external onlyAdminOrYieldManager {
        if (IERC20(token).balanceOf(address(this)) < amount) {
            revert InsufficientBalance();
        }

        IERC20(token).safeTransfer(address(YIELD_MANAGER), amount);
    }
}
