// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Predeploys } from "../libraries/Predeploys.sol";
import { StandardBridge } from "../universal/StandardBridge.sol";
import { CrossDomainMessenger } from "../universal/CrossDomainMessenger.sol";
import { ISemver } from "../universal/ISemver.sol";
import { SafeCall } from "../libraries/SafeCall.sol";
import { AddressAliasHelper } from "../vendor/AddressAliasHelper.sol";
import { Patex, YieldMode, GasMode } from "../L2/Patex.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";

/// @custom:proxied
/// @custom:predeploy 0x4300000000000000000000000000000000000005
/// @title L2PatexBridge
/// @notice The L2PatexBridge is responsible for transfering ETH and USDB tokens between L1 and
///         L2. In the case that an ERC20 token is native to L2, it will be escrowed within this
///         contract.
contract L2PatexBridge is StandardBridge, ISemver {

    Postdeploys public postdeploys;
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer
    function initialize(Postdeploys _postdeploys, StandardBridge _otherBridge) public initializer {
        __StandardBridge_init({ 
            _messenger: CrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER),
            _otherBridge: StandardBridge(_otherBridge)
        });

        postdeploys = _postdeploys;
        Patex(Postdeploys(postdeploys).PATEX()).configureContract(
            address(this),
            YieldMode.VOID,
            GasMode.VOID,
            address(0xdead) /// don't set a governor
        );
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    receive() external payable override onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, hex"");
    }

    /// @notice Modified StandardBridge.finalizeBridgeETH function to allow calls directly from
    ///         the L1PatexBridge without going through a messenger.
    /// @notice See { StandardBridge-finalizeBridgeETH }
    function finalizeBridgeETHDirect(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        payable
    {
        require(AddressAliasHelper.undoL1ToL2Alias(msg.sender) == address(otherBridge), "L2PatexBridge: function can only be called from the other bridge");
        require(msg.value == _amount, "L2PatexBridge: amount sent does not match amount required");
        require(_to != address(this), "L2PatexBridge: cannot send to self");
        require(_to != address(messenger), "L2PatexBridge: cannot send to messenger");

        // Emit the correct events. By default this will be _amount, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitETHBridgeFinalized(_from, _to, _amount, _extraData);

        bool success = SafeCall.call(_to, gasleft(), _amount, hex"");
        require(success, "L2PatexBridge: ETH transfer failed");
    }

    /// @notice Wrapper to only accept USDB withdrawals.
    /// @notice See { StandardBridge-_initiateBridgeERC20 }
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
        override
    {
        require(_localToken == Postdeploys(postdeploys).USDB(), "L2PatexBridge: only USDB can be withdrawn from this bridge.");
        require(_isCorrectTokenPair(Postdeploys(postdeploys).USDB(), _remoteToken), "L2PatexBridge: wrong remote token for USDB.");
        super._initiateBridgeERC20(_localToken, _remoteToken, _from, _to, _amount, _minGasLimit, _extraData);
    }
}
