// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/* Contract Imports */
import { PatexMintableERC20 } from "../universal/PatexMintableERC20.sol";
import { Semver } from "./Semver.sol";

/**
 * @custom:proxied
 * @custom:predeployed 0x4200000000000000000000000000000000000012
 * @title PatexMintableERC20Factory
 * @notice PatexMintableERC20Factory is a factory contract that generates PatexMintableERC20
 *         contracts on the network it's deployed to. Simplifies the deployment process for users
 *         who may be less familiar with deploying smart contracts. Designed to be backwards
 *         compatible with the older StandardL2ERC20Factory contract.
 */
contract PatexMintableERC20Factory is Semver {
    /**
     * @notice Address of the StandardBridge on this chain.
     */
    address public immutable BRIDGE;

    /**
     * @custom:legacy
     * @notice Emitted whenever a new PatexMintableERC20 is created. Legacy version of the newer
     *         PatexMintableERC20Created event. We recommend relying on that event instead.
     *
     * @param remoteToken Address of the token on the remote chain.
     * @param localToken  Address of the created token on the local chain.
     */
    event StandardL2TokenCreated(address indexed remoteToken, address indexed localToken);

    /**
     * @notice Emitted whenever a new PatexMintableERC20 is created.
     *
     * @param localToken  Address of the created token on the local chain.
     * @param remoteToken Address of the corresponding token on the remote chain.
     * @param deployer    Address of the account that deployed the token.
     */
    event PatexMintableERC20Created(
        address indexed localToken,
        address indexed remoteToken,
        address deployer
    );

    /**
     * @custom:semver 1.1.0
     *
     * @notice The semver MUST be bumped any time that there is a change in
     *         the PatexMintableERC20 token contract since this contract
     *         is responsible for deploying PatexMintableERC20 contracts.
     *
     * @param _bridge Address of the StandardBridge on this chain.
     */
    constructor(address _bridge) Semver(1, 1, 0) {
        BRIDGE = _bridge;
    }

    /**
     * @custom:legacy
     * @notice Creates an instance of the PatexMintableERC20 contract. Legacy version of the
     *         newer createPatexMintableERC20 function, which has a more intuitive name.
     *
     * @param _remoteToken Address of the token on the remote chain.
     * @param _name        ERC20 name.
     * @param _symbol      ERC20 symbol.
     *
     * @return Address of the newly created token.
     */
    function createStandardL2Token(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        return createPatexMintableERC20(_remoteToken, _name, _symbol);
    }

    /**
     * @notice Creates an instance of the PatexMintableERC20 contract.
     *
     * @param _remoteToken Address of the token on the remote chain.
     * @param _name        ERC20 name.
     * @param _symbol      ERC20 symbol.
     *
     * @return Address of the newly created token.
     */
    function createPatexMintableERC20(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    ) public returns (address) {
        require(
            _remoteToken != address(0),
            "PatexMintableERC20Factory: must provide remote token address"
        );

        address localToken = address(
            new PatexMintableERC20(BRIDGE, _remoteToken, _name, _symbol)
        );

        // Emit the old event too for legacy support.
        emit StandardL2TokenCreated(_remoteToken, localToken);

        // Emit the updated event. The arguments here differ from the legacy event, but
        // are consistent with the ordering used in StandardBridge events.
        emit PatexMintableERC20Created(localToken, _remoteToken, msg.sender);

        return localToken;
    }
}
