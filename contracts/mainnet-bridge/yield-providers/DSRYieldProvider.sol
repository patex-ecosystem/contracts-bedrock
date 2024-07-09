// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { FixedPointMathLib } from "solmate/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldProvider } from "./YieldProvider.sol";
import { YieldManager } from "../YieldManager.sol";

interface IDsrManager {
    function join(address usr, uint256 wad) external;
    function exit(address usr, uint256 wad) external;
    function pot() external view returns (address);
    function daiJoin() external view returns (address);
    function pieOf(address) external view returns (uint256);
}

interface IPot {
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function dsr() external view returns (uint256);
}

interface ILive {
    function live() external view returns (uint256);
}

interface IInsurance {
    function coverLoss(address token, uint256 amount) external;
}

/// @title DSRYieldManager
/// @notice Provider for the DAI Savings Rate (USD) yield source.
contract DSRYieldProvider is YieldProvider {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IDsrManager public constant DSR_MANAGER = IDsrManager(0x373238337Bfe1146fb49989fc222523f83081dDb);

    uint256 constant RAY = 10 ** 27;

    /// @param _yieldManager Address of the yield manager for the underlying
    ///        yield asset of this provider.
    constructor(YieldManager _yieldManager) YieldProvider(_yieldManager) {}

    /// @inheritdoc YieldProvider
    function initialize() external override onlyDelegateCall {
        DAI.approve(address(DSR_MANAGER), type(uint256).max);
    }

    function name() public pure override returns (string memory) {
        return "DSRYieldProvider";
    }

    /// @inheritdoc YieldProvider
    function isStakingEnabled(address token) public view override returns (bool) {
        return token == address(DAI) &&
            ILive(DSR_MANAGER.pot()).live() == 1 &&
            ILive(DSR_MANAGER.daiJoin()).live() == 1;
    }

    /// @inheritdoc YieldProvider
    function stakedBalance() public view override returns (uint256) {
        IPot pot = IPot(DSR_MANAGER.pot());
        uint256 chi = FixedPointMathLib.mulDivDown(
            FixedPointMathLib.rpow(
                pot.dsr(),
                block.timestamp - pot.rho(),
                RAY
            ),
            pot.chi(),
            RAY
        );
        return FixedPointMathLib.mulDivDown(
            DSR_MANAGER.pieOf(address(YIELD_MANAGER)),
            chi,
            RAY
        );
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
        if (amount > 0) {
            DSR_MANAGER.join(address(YIELD_MANAGER), amount);
        }
    }

    /// @inheritdoc YieldProvider
    function unstake(uint256 amount) external override onlyDelegateCall returns (uint256 pending, uint256 claimed) {
        if (amount > 0) {
            DSR_MANAGER.exit(address(YIELD_MANAGER), amount);
        }

        pending = 0;
        claimed = amount;
    }

    function _recordPending(uint256) internal pure override {
        revert("DSRYieldProvider: recordPending not supported");
    }

    function _recordClaimed(uint256 claimed, uint256 expected) internal override {
        emit Claimed(id(), claimed, expected);
    }

    /// @inheritdoc YieldProvider
    function payInsurancePremium(uint256 amount) external override onlyDelegateCall {
        require(supportsInsurancePayment(), "insurance not supported");
        if (amount > 0) {
            DSR_MANAGER.exit(address(YIELD_MANAGER), amount);
            DAI.transfer(YIELD_MANAGER.insurance(), amount);
        }

        emit InsurancePremiumPaid(id(), amount);
    }

    /// @inheritdoc YieldProvider
    function withdrawFromInsurance(uint256 amount) external override onlyDelegateCall {
        require(supportsInsurancePayment(), "insurance not supported");
        IInsurance(YIELD_MANAGER.insurance()).coverLoss(address(DAI), amount);

        emit InsuranceWithdrawn(id(), amount);
    }

    /// @inheritdoc YieldProvider
    function insuranceBalance() public view override returns (uint256) {
        return DAI.balanceOf(YIELD_MANAGER.insurance());
    }
}
