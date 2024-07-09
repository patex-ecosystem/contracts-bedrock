// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeCall } from "../libraries/SafeCall.sol";
import { StandardBridge } from "../universal/StandardBridge.sol";
import { L2PatexBridge } from "./L2PatexBridge.sol";
import { ISemver } from "../universal/ISemver.sol";
import { CrossDomainMessenger } from "../universal/CrossDomainMessenger.sol";
import { PatexPortal } from "../L1/PatexPortal.sol";
import { USDYieldManager } from "./USDYieldManager.sol";
import { ETHYieldManager } from "./ETHYieldManager.sol";
import { USDB } from "../L2/USDB.sol";
import { USDConversions } from "./USDConversions.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";

/// @custom:proxied
/// @title L1PatexBridge
/// @notice The L1PatexBridge is responsible for transferring ETH and yield-bearing ERC20 tokens between L1 and L2.
///
///         The current implementation converts all deposited USD tokens to DAI before bridging them to L2 to mint USDB.
///         Hence, the amount of USDB that is minted on L2 will be equal to the amount of DAI that is received on L1.
///         This is done to simplify the yield management, as DSR is the only yield provider that is currently supported.
///         When non-DAI USD tokens are deposited, the user is expected to provide the minimum amount of DAI that should
///         be received (i.e. the minimum amount of USDB that should be minted on L2). This amount must be specified
///         in the extraData field of the deposit transaction (uint256 minAmountInWad).
contract L1PatexBridge is StandardBridge, ISemver {
    using SafeERC20 for IERC20;

    struct YieldToken {
        bool approved;
        uint8 decimals;
        address provider;
        bool reportStakedBalance;
    }

    /// @notice Numerator for dynamic overhead added to the base gas for a message.
    uint64 public constant MIN_GAS_DYNAMIC_OVERHEAD_NUMERATOR = 64;

    /// @notice Denominator for dynamic overhead added to the base gas for a message.
    uint64 public constant MIN_GAS_DYNAMIC_OVERHEAD_DENOMINATOR = 63;

    /// @notice Mapping of potential deposit tokens to whether they're
    ///         approved as USD yield tokens and additional metadata.
    mapping(address => YieldToken) public usdYieldTokens;

    /// @notice Mapping of potential deposit tokens to whether they're
    ///         approved as ETH yield tokens and additional metadata.
    mapping(address => YieldToken) public ethYieldTokens;

    /// @notice Address of the USD Yield Manager.
    USDYieldManager public usdYieldManager;

    /// @notice Address of the ETH Yield Manager.
    ETHYieldManager public ethYieldManager;

    /// @notice Address of the PatexPortal.
    PatexPortal public portal;

    Postdeploys public postdeploys;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @custom:semver 1.0.0
    /// @notice Constructs the L1PatexBridge contract.
    constructor() {
        initialize({
            _portal: PatexPortal(payable(address(0))),
            _messenger: CrossDomainMessenger(address(0)),
            _usdYieldManager: USDYieldManager(payable(address(0))),
            _ethYieldManager: ETHYieldManager(payable(address(0))),
            _postdeploys: Postdeploys(address(0)),
            _otherBridge: StandardBridge(payable(address(0)))
        });
    }

    /// @notice Initializer
    /// @param _portal          Address of the PatexPortal.
    /// @param _messenger       Address of the L1CrossDomainMessenger.
    /// @param _usdYieldManager Address of the USDYieldManager.
    /// @param _ethYieldManager Address of the ETHYieldManager.
    function initialize(
        PatexPortal _portal,
        CrossDomainMessenger _messenger,
        USDYieldManager _usdYieldManager,
        ETHYieldManager _ethYieldManager,
        Postdeploys _postdeploys,
        StandardBridge _otherBridge
    ) public reinitializer(2) {
        portal = _portal;
        __StandardBridge_init(_messenger, _otherBridge);
        usdYieldManager = _usdYieldManager;
        ethYieldManager = _ethYieldManager;
        postdeploys = _postdeploys;
    }

    /// @notice Add/remove an approved USD yield token.
    /// @param token               Address of token.
    /// @param approved            Whether the token is an approved yield token.
    /// @param decimals            Number of token decimals.
    /// @param provider            Address of the yield provider for the token.
    /// @param reportStakedBalance Whether a deposit needs to be reported to the yield provider.
    function setUSDYieldToken(
        address token,
        bool approved,
        uint8 decimals,
        address provider,
        bool reportStakedBalance
    ) external {
        require(msg.sender == usdYieldManager.owner(), "L1PatexBridge: only USDYieldManager owner can call");
        usdYieldTokens[token] = YieldToken({
            approved: approved,
            decimals: decimals,
            provider: provider,
            reportStakedBalance: reportStakedBalance
        });
    }

    /// @notice Add/remove an approved ETH yield token.
    /// @param token               Address of token.
    /// @param approved            Whether the token is an approved yield token.
    /// @param decimals            Number of token decimals.
    /// @param provider            Address of the yield provider for the token.
    /// @param reportStakedBalance Whether a deposit needs to be reported to the yield provider.
    function setETHYieldToken(
        address token,
        bool approved,
        uint8 decimals,
        address provider,
        bool reportStakedBalance
    ) external {
        require(msg.sender == ethYieldManager.owner(), "L1PatexBridge: only ETHYieldManager owner can call");
        require(token != address(0));
        ethYieldTokens[token] = YieldToken({
            approved: approved,
            decimals: decimals,
            provider: provider,
            reportStakedBalance: reportStakedBalance
        });
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    receive() external payable override onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, hex"");
    }

    /// Patex: This function is modified from StandardBridge to enable
    /// discounted withdrawals on L1. The `msg.value` check is
    /// less strict and `msg.value` is used instead of `_amount`
    /// in the following steps.
    /// @inheritdoc StandardBridge
    function finalizeBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        payable
        override
        onlyOtherBridge
    {
        // Patex: Accept discounted `msg.value`
        require(msg.value <= _amount, "L1PatexBridge: amount sent exceeds amount required");
        require(_to != address(this), "L1PatexBridge: cannot send to self");
        require(_to != address(messenger), "L1PatexBridge: cannot send to messenger");

        // Emit the correct events. By default this will be _amount, but child
        // contracts may override this function in order to emit legacy events as well.
        // Patex: replace `_amount` with `msg.value`
        _emitETHBridgeFinalized(_from, _to, msg.value, _extraData);

        // Patex: replace `_amount` with `msg.value`
        bool success = SafeCall.call(_to, gasleft(), msg.value, hex"");
        require(success, "L2PatexBridge: ETH transfer failed");
    }

    /// @notice Finalizes an ERC20 bridge on this chain. Can only be triggered by the other
    ///         PatexBridge contract on the remote chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        override
        onlyOtherBridge
    {
        require(_to != address(this), "StandardBridge: cannot send to self");
        require(_to != address(messenger), "StandardBridge: cannot send to messenger");

        require(_localToken == usdYieldManager.TOKEN(), "L1PatexBridge: unsupported local token");
        require(_remoteToken == Postdeploys(postdeploys).USDB(), "L1PatexBridge: only USDB can be withdrawn through this bridge");

        // Emit the correct events. By default this will be ERC20BridgeFinalized, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        usdYieldManager.requestWithdrawal(_to, _amount);
    }

    /// @notice Sends approved yield-bearing ERC20 tokens to a receiver's address on the other chain.
    ///         Only USDB or ETH are accepted as _remoteToken. ETH-based tokens are sent to the
    ///         Patex Portal.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction. For bridging yield-bearing USD tokens (except DAI),
    ///                     the extra data should contain the minimum amount of tokens in WAD to be minted.
    ///                     When the deposited USD tokens are converted to DAI, it ensures that the amount
    ///                     of DAI received (and hence the amount of USDB minted) is at least the minimum
    ///                     amount specified.
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
        YieldToken memory usdYieldToken = usdYieldTokens[_localToken];
        YieldToken memory ethYieldToken = ethYieldTokens[_localToken];
        if (usdYieldToken.approved) {
            require(_remoteToken == Postdeploys(postdeploys).USDB(), "L1PatexBridge: this token can only be bridged to USDB");
            IERC20(_localToken).safeTransferFrom(_from, address(usdYieldManager), _amount);

            uint256 amountWad = USDConversions._convertDecimals(_amount, usdYieldToken.decimals, USDConversions.WAD_DECIMALS);
            uint256 amountToMintWad = usdYieldManager.convert(_localToken, amountWad, _extraData);

            // Update the yield provider with the staked deposit.
            if (usdYieldToken.reportStakedBalance) {
                require(usdYieldToken.provider != address(0));
                usdYieldManager.recordStakedDeposit(usdYieldToken.provider, amountToMintWad);
            }

            // Emit the correct events. By default this will be ERC20BridgeInitiated, but child
            // contracts may override this function in order to emit legacy events as well.
            _emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, amountToMintWad, _extraData);

            messenger.sendMessage(
                Postdeploys(postdeploys).L2_PATEX_BRIDGE(),
                abi.encodeWithSelector(
                    StandardBridge.finalizeBridgeERC20.selector,
                    Postdeploys(postdeploys).USDB(),
                    usdYieldManager.TOKEN(),
                    _from,
                    _to,
                    amountToMintWad,
                    _extraData
                ),
                _minGasLimit
            );

        } else if (ethYieldToken.approved) {
            require(_remoteToken == address(0), "L1PatexBridge: this token can only be bridged to ETH");
            IERC20(_localToken).safeTransferFrom(_from, address(ethYieldManager), _amount);

            // Update the yield provider with the staked deposit.
            if (ethYieldToken.reportStakedBalance) {
                require(ethYieldToken.provider != address(0));
                ethYieldManager.recordStakedDeposit(ethYieldToken.provider, _amount);
            }

            uint256 amountWad = USDConversions._convertDecimals(_amount, ethYieldToken.decimals, USDConversions.WAD_DECIMALS);

            // Emit the correct events. By default this will be ERC20BridgeInitiated, but child
            // contracts may override this function in order to emit legacy events as well.
            _emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, amountWad, _extraData);

            // Message has to be sent to the PatexPortal directly because we have to
            // request the L2 message has value without sending ETH.
            portal.depositTransaction(
                Postdeploys(postdeploys).L2_PATEX_BRIDGE(),
                amountWad,
                baseGas(_minGasLimit),
                false,
                abi.encodeWithSelector(
                    L2PatexBridge.finalizeBridgeETHDirect.selector,
                    _from,
                    _to,
                    amountWad,
                    _extraData
                )
            );
        } else {
            revert("L1PatexBridge: bridge token is not supported");
        }
    }

    /// @notice Computes the amount of gas required to guarantee that a given deposit will be
    ///         received on the other chain without running out of gas.
    /// @param _minGasLimit Minimum desired gas limit when deposit goes to target.
    /// @return Amount of gas required to guarantee deposit receipt.
    function baseGas(uint32 _minGasLimit) public pure returns (uint64) {
        return
        // Constant overhead
        RECEIVE_DEFAULT_GAS_LIMIT
        // Dynamic overhead (EIP-150)
        + ((_minGasLimit * MIN_GAS_DYNAMIC_OVERHEAD_NUMERATOR) / MIN_GAS_DYNAMIC_OVERHEAD_DENOMINATOR);
    }
}
