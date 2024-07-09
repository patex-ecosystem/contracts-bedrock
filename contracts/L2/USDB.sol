// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { ERC20Rebasing } from "./ERC20Rebasing.sol";
import { SharesBase } from "./Shares.sol";
import { CrossDomainMessenger } from "../universal/CrossDomainMessenger.sol";
import { StandardBridge } from "../universal/StandardBridge.sol";
import { IPatexMintableERC20 } from "../universal/IPatexMintableERC20.sol";
import { Semver } from "../universal/Semver.sol";
import { Patex, YieldMode, GasMode } from "./Patex.sol";
import { Postdeploys } from "./Postdeploys.sol";

/// @custom:proxied
/// @custom:predeploy 0x4300000000000000000000000000000000000003
/// @title USDB
/// @notice Rebasing ERC20 token with the share price determined by an L1
///         REPORTER. Conforms PatexMintableERC20 interface to allow mint/burn
///         interactions from the L1PatexBridge.
contract USDB is ERC20Rebasing, Semver, IPatexMintableERC20 {
    /// @notice Address of the corresponding version of this token on the remote chain.
    address public immutable REMOTE_TOKEN;

    /// @notice Address of the PatexBridge on this network.
    address public immutable BRIDGE;

    Postdeploys public postdeploys;

    error CallerIsNotBridge();

    /// @notice A modifier that only allows the bridge to call
    modifier onlyBridge() {
        if (msg.sender != BRIDGE) {
            revert CallerIsNotBridge();
        }
        _;
    }

    /// @custom:semver 1.0.0
    /// @param _usdYieldManager Address of the USD Yield Manager. SharesBase yield reporter.
    /// @param _l2Bridge        Address of the L2 Patex bridge.
    /// @param _remoteToken     Address of the corresponding L1 token.
    constructor(address _usdYieldManager, address _l2Bridge, address _remoteToken)
        ERC20Rebasing(_usdYieldManager, 18)
        Semver(1, 0, 0)
    {
        BRIDGE = _l2Bridge;
        REMOTE_TOKEN = _remoteToken;
        _disableInitializers();
    }

    /// @notice Initializer
    function initialize(Postdeploys _postdeploys) public initializer {
        __ERC20Rebasing_init("USDB", "USDB", 1e9);

        postdeploys = _postdeploys;
        Patex(Postdeploys(postdeploys).PATEX()).configureContract(
            address(this),
            YieldMode.VOID,
            GasMode.VOID,
            address(0xdead) /// don't set a governor
        );
    }

    /// @notice ERC165 interface check function.
    /// @param _interfaceId Interface ID to check.
    /// @return Whether or not the interface is supported by this contract.
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        // Interface corresponding to the updated PatexMintableERC20.
        bytes4 iface2 = type(IPatexMintableERC20).interfaceId;
        return _interfaceId == iface1 || _interfaceId == iface2;
    }

    /// @custom:legacy
    /// @notice Legacy getter for REMOTE_TOKEN.
    function remoteToken() public view returns (address) {
        return REMOTE_TOKEN;
    }

    /// @custom:legacy
    /// @notice Legacy getter for BRIDGE.
    function bridge() public view returns (address) {
        return BRIDGE;
    }

    /// @notice Allows the StandardBridge on this network to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(address _to, uint256 _amount)
        external
        virtual
        onlyBridge
    {
        if (_to == address(0)) {
            revert TransferToZeroAddress();
        }

        _deposit(_to, _amount);
        emit Transfer(address(0), _to, _amount);
    }

    /// @notice Allows the StandardBridge on this network to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(address _from, uint256 _amount)
        external
        virtual
        onlyBridge
    {
        if (_from == address(0)) {
            revert TransferFromZeroAddress();
        }

        _withdraw(_from, _amount);
        emit Transfer(_from, address(0), _amount);
    }

    /**
     * @dev The version parameter for the EIP712 domain.
     */
    function _EIP712Version() internal override view returns (string memory) {
        return version();
    }
}
