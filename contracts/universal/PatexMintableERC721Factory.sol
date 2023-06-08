// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { PatexMintableERC721 } from "./PatexMintableERC721.sol";
import { Semver } from "./Semver.sol";

/**
 * @title PatexMintableERC721Factory
 * @notice Factory contract for creating PatexMintableERC721 contracts.
 */
contract PatexMintableERC721Factory is Semver {
    /**
     * @notice Address of the ERC721 bridge on this network.
     */
    address public immutable BRIDGE;

    /**
     * @notice Chain ID for the remote network.
     */
    uint256 public immutable REMOTE_CHAIN_ID;

    /**
     * @notice Tracks addresses created by this factory.
     */
    mapping(address => bool) public isPatexMintableERC721;

    /**
     * @notice Emitted whenever a new PatexMintableERC721 contract is created.
     *
     * @param localToken  Address of the token on the this domain.
     * @param remoteToken Address of the token on the remote domain.
     * @param deployer    Address of the initiator of the deployment
     */
    event PatexMintableERC721Created(
        address indexed localToken,
        address indexed remoteToken,
        address deployer
    );

    /**
     * @custom:semver 1.1.0
     * @notice The semver MUST be bumped any time that there is a change in
     *         the PatexMintableERC721 token contract since this contract
     *         is responsible for deploying PatexMintableERC721 contracts.
     *
     * @param _bridge Address of the ERC721 bridge on this network.
     * @param _remoteChainId Chain ID for the remote network.
     */
    constructor(address _bridge, uint256 _remoteChainId) Semver(1, 1, 0) {
        BRIDGE = _bridge;
        REMOTE_CHAIN_ID = _remoteChainId;
    }

    /**
     * @notice Creates an instance of the standard ERC721.
     *
     * @param _remoteToken Address of the corresponding token on the other domain.
     * @param _name        ERC721 name.
     * @param _symbol      ERC721 symbol.
     */
    function createPatexMintableERC721(
        address _remoteToken,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        require(
            _remoteToken != address(0),
            "PatexMintableERC721Factory: L1 token address cannot be address(0)"
        );

        address localToken = address(
            new PatexMintableERC721(BRIDGE, REMOTE_CHAIN_ID, _remoteToken, _name, _symbol)
        );

        isPatexMintableERC721[localToken] = true;
        emit PatexMintableERC721Created(localToken, _remoteToken, msg.sender);

        return localToken;
    }
}
