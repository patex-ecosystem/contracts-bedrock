// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Initializable } from "../openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { Semver } from "../universal/Semver.sol";
import { GasMode, IGas } from "./Gas.sol";

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

interface IYield {
    function configure(address contractAddress, uint8 flags) external returns (uint256);
    function claim(address contractAddress, address recipientOfYield, uint256 desiredAmount) external returns (uint256);
    function getClaimableAmount(address contractAddress) external view returns (uint256);
    function getConfiguration(address contractAddress) external view returns (uint8);
}

interface IPatex{
    // configure
    function configureContract(address contractAddress, YieldMode _yield, GasMode gasMode, address governor) external;
    function configure(YieldMode _yield, GasMode gasMode, address governor) external;

    // base configuration options
    function configureClaimableYield() external;
    function configureClaimableYieldOnBehalf(address contractAddress) external;
    function configureAutomaticYield() external;
    function configureAutomaticYieldOnBehalf(address contractAddress) external;
    function configureVoidYield() external;
    function configureVoidYieldOnBehalf(address contractAddress) external;
    function configureClaimableGas() external;
    function configureClaimableGasOnBehalf(address contractAddress) external;
    function configureVoidGas() external;
    function configureVoidGasOnBehalf(address contractAddress) external;
    function configureGovernor(address _governor) external;
    function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external;

    // claim yield
    function claimYield(address contractAddress, address recipientOfYield, uint256 amount) external returns (uint256);
    function claimAllYield(address contractAddress, address recipientOfYield) external returns (uint256);

    // claim gas
    function claimAllGas(address contractAddress, address recipientOfGas) external returns (uint256);
    // NOTE: can be off by 1 bip
    function claimGasAtMinClaimRate(address contractAddress, address recipientOfGas, uint256 minClaimRateBips) external returns (uint256);
    function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256);
    function claimGas(address contractAddress, address recipientOfGas, uint256 gasToClaim, uint256 gasSecondsToConsume) external returns (uint256);

    // read functions
    function readClaimableYield(address contractAddress) external view returns (uint256);
    function readYieldConfiguration(address contractAddress) external view returns (uint8);
    function readGasParams(address contractAddress) external view returns (uint256 etherSeconds, uint256 etherBalance, uint256 lastUpdated, GasMode);
}

contract Patex is IPatex, Initializable, Semver {
    address public immutable YIELD_CONTRACT;

    address public gasContract;

    mapping(address => address) public governorMap;

    constructor(address _yieldContract) Semver(1, 0, 0) {     
        YIELD_CONTRACT = _yieldContract;
        _disableInitializers();
    }

    function initialize(
        address _gasContract
    ) public initializer {
        gasContract = _gasContract;
    }

    /**
     * @notice Checks if the caller is the governor of the contract
     * @param contractAddress The address of the contract
     * @return A boolean indicating if the caller is the governor
     */
    function isGovernor(address contractAddress) public view returns (bool) {
        return msg.sender == governorMap[contractAddress];
    }
    /**
     * @notice Checks if the governor is not set for the contract
     * @param contractAddress The address of the contract
     * @return boolean indicating if the governor is not set
     */
    function governorNotSet(address contractAddress) internal view returns (bool) {
        return governorMap[contractAddress] == address(0);
    }
    /**
     * @notice Checks if the caller is authorized
     * @param contractAddress The address of the contract
     * @return A boolean indicating if the caller is authorized
     */
    function isAuthorized(address contractAddress) public view returns (bool) {
        return isGovernor(contractAddress) || (governorNotSet(contractAddress) && msg.sender == contractAddress);
    }

    /**
     * @notice contract configures its yield and gas modes and sets the governor. called by contract
     * @param _yieldMode The yield mode to be set
     * @param _gasMode The gas mode to be set
     * @param governor The address of the governor to be set
     */
    function configure(YieldMode _yieldMode, GasMode _gasMode, address governor) external {
        // requires that no governor is set for contract
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        // set governor
        governorMap[msg.sender] = governor;
        // set gas mode
        IGas(gasContract).setGasMode(msg.sender, _gasMode);
        // set yield mode
        IYield(YIELD_CONTRACT).configure(msg.sender, uint8(_yieldMode));
    }

    /**
     * @notice Configures the yield and gas modes and sets the governor for a specific contract. called by authorized user
     * @param contractAddress The address of the contract to be configured
     * @param _yieldMode The yield mode to be set
     * @param _gasMode The gas mode to be set
     * @param _newGovernor The address of the new governor to be set
     */
    function configureContract(address contractAddress, YieldMode _yieldMode, GasMode _gasMode, address _newGovernor) external {
        // only allow governor, or if no governor is set, the contract itself to configure
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        // set governor
        governorMap[contractAddress] = _newGovernor;
        // set gas mode
        IGas(gasContract).setGasMode(contractAddress, _gasMode);
        // set yield mode
        IYield(YIELD_CONTRACT).configure(contractAddress, uint8(_yieldMode));
    }

    /**
     * @notice Configures the yield mode to CLAIMABLE for the contract that calls this function
     */
    function configureClaimableYield() external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(msg.sender, uint8(YieldMode.CLAIMABLE));
    }

    /**
     * @notice Configures the yield mode to CLAIMABLE for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureClaimableYieldOnBehalf(address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(contractAddress, uint8(YieldMode.CLAIMABLE));
    }

    /**
     * @notice Configures the yield mode to AUTOMATIC for the contract that calls this function
     */
    function configureAutomaticYield() external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(msg.sender, uint8(YieldMode.AUTOMATIC));
    }

    /**
     * @notice Configures the yield mode to AUTOMATIC for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureAutomaticYieldOnBehalf(address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(contractAddress, uint8(YieldMode.AUTOMATIC));
    }

    /**
     * @notice Configures the yield mode to VOID for the contract that calls this function
     */
    function configureVoidYield() external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(msg.sender, uint8(YieldMode.VOID));
    }

    /**
     * @notice Configures the yield mode to VOID for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureVoidYieldOnBehalf(address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        IYield(YIELD_CONTRACT).configure(contractAddress, uint8(YieldMode.VOID));
    }

    /**
     * @notice Configures the gas mode to CLAIMABLE for the contract that calls this function
     */
    function configureClaimableGas() external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        IGas(gasContract).setGasMode(msg.sender, GasMode.CLAIMABLE);
    }

    /**
     * @notice Configures the gas mode to CLAIMABLE for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureClaimableGasOnBehalf(address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        IGas(gasContract).setGasMode(contractAddress, GasMode.CLAIMABLE);
    }

    /**
     * @notice Configures the gas mode to VOID for the contract that calls this function
     */
    function configureVoidGas() external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        IGas(gasContract).setGasMode(msg.sender, GasMode.VOID);
    }

    /**
     * @notice Configures the gas mode to void for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureVoidGasOnBehalf(address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        IGas(gasContract).setGasMode(contractAddress, GasMode.VOID);
    }

    /**
     * @notice Configures the governor for the contract that calls this function
     */
    function configureGovernor(address _governor) external {
        require(isAuthorized(msg.sender), "not authorized to configure contract");
        governorMap[msg.sender] = _governor;
    }

    /**
     * @notice Configures the governor for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract to be configured
     */
    function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external {
        require(isAuthorized(contractAddress), "not authorized to configure contract");
        governorMap[contractAddress] = _newGovernor;
    }


    // claim methods

    /**
     * @notice Claims yield for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract for which yield is to be claimed
     * @param recipientOfYield The address of the recipient of the yield
     * @param amount The amount of yield to be claimed
     * @return The amount of yield that was claimed
     */
    function claimYield(address contractAddress, address recipientOfYield, uint256 amount) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not authorized to claim yield");
        return  IYield(YIELD_CONTRACT).claim(contractAddress, recipientOfYield, amount);
    }
    /**
     * @notice Claims all yield for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract for which all yield is to be claimed
     * @param recipientOfYield The address of the recipient of the yield
     * @return The amount of yield that was claimed
     */
    function claimAllYield(address contractAddress, address recipientOfYield) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not authorized to claim yield");
        uint256 amount = IYield(YIELD_CONTRACT).getClaimableAmount(contractAddress);
        return  IYield(YIELD_CONTRACT).claim(contractAddress, recipientOfYield, amount);
    }

    /**
     * @notice Claims all gas for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract for which all gas is to be claimed
     * @param recipientOfGas The address of the recipient of the gas
     * @return The amount of gas that was claimed
     */
    function claimAllGas(address contractAddress, address recipientOfGas) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not allowed to claim all gas");
        return IGas(gasContract).claimAll(contractAddress, recipientOfGas);
    }

    /**
     * @notice Claims gas at a minimum claim rate for a specific contract, with error rate '1'. Called by an authorized user
     * @param contractAddress The address of the contract for which gas is to be claimed
     * @param recipientOfGas The address of the recipient of the gas
     * @param minClaimRateBips The minimum claim rate in basis points
     * @return The amount of gas that was claimed
     */
    function claimGasAtMinClaimRate(address contractAddress, address recipientOfGas, uint256 minClaimRateBips) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not allowed to claim gas at min claim rate");
        return IGas(gasContract).claimGasAtMinClaimRate(contractAddress, recipientOfGas, minClaimRateBips);
    }

    /**
     * @notice Claims gas available to be claimed at max claim rate for a specific contract. Called by an authorized user
     * @param contractAddress The address of the contract for which maximum gas is to be claimed
     * @param recipientOfGas The address of the recipient of the gas
     * @return The amount of gas that was claimed
     */
    function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not allowed to claim max gas");
        return IGas(gasContract).claimMax(contractAddress, recipientOfGas);
    }
    /**
     * @notice Claims a specific amount of gas for a specific contract. claim rate governed by integral of gas over time
     * @param contractAddress The address of the contract for which gas is to be claimed
     * @param recipientOfGas The address of the recipient of the gas
     * @param gasToClaim The amount of gas to be claimed
     * @param gasSecondsToConsume The amount of gas seconds to consume
     * @return The amount of gas that was claimed
     */
    function claimGas(address contractAddress, address recipientOfGas, uint256 gasToClaim, uint256 gasSecondsToConsume) external returns (uint256) {
        require(isAuthorized(contractAddress), "Not allowed to claim gas");
        return IGas(gasContract).claim(contractAddress, recipientOfGas, gasToClaim, gasSecondsToConsume);
    }

    /**
     * @notice Reads the claimable yield for a specific contract
     * @param contractAddress The address of the contract for which the claimable yield is to be read
     * @return claimable yield
     */
    function readClaimableYield(address contractAddress) public view returns (uint256) {
        return IYield(YIELD_CONTRACT).getClaimableAmount(contractAddress);
    }
    /**
     * @notice Reads the yield configuration for a specific contract
     * @param contractAddress The address of the contract for which the yield configuration is to be read
     * @return uint8 representing yield enum
     */

    function readYieldConfiguration(address contractAddress) public view returns (uint8) {
        return IYield(YIELD_CONTRACT).getConfiguration(contractAddress);
    }
    /**
     * @notice Reads the gas parameters for a specific contract
     * @param contractAddress The address of the contract for which the gas parameters are to be read
     * @return uint256 representing the accumulated ether seconds
     * @return uint256 representing ether balance
     * @return uint256 representing last update timestamp
     * @return GasMode representing the gas mode (VOID, CLAIMABLE)
     */
    function readGasParams(address contractAddress) public view returns (uint256, uint256, uint256, GasMode) {
        return IGas(gasContract).readGasParams(contractAddress);
    }
}
