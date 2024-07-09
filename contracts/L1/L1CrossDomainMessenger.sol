// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "../libraries/Predeploys.sol";
import { SafeCall } from "../libraries/SafeCall.sol";
import { Hashing } from "../libraries/Hashing.sol";
import { Encoding } from "../libraries/Encoding.sol";
import { PatexPortal } from "./PatexPortal.sol";
import { CrossDomainMessenger } from "../universal/CrossDomainMessenger.sol";
import { ISemver } from "../universal/ISemver.sol";
import { Constants } from "../libraries/Constants.sol";

/**
 * @custom:proxied
 * @title L1CrossDomainMessenger
 * @notice The L1CrossDomainMessenger is a message passing interface between L1 and L2 responsible
 *         for sending and receiving data on the L1 side. Users are encouraged to use this
 *         interface instead of interacting with lower-level contracts directly.
 */
contract L1CrossDomainMessenger is CrossDomainMessenger, ISemver {
    /**
     * @notice Address of the PatexPortal.
     */
    PatexPortal public PORTAL;

    /// @notice Add storage gap for future Optimism contract upgrades.
    uint256[50] private __gap;

    /// @notice Patex addition to record the withdrawal amount for
    ///         discounted withdrawals.
    mapping(bytes32 => uint256) public discountedValues;

    /// @notice Semantic version.
    /// @custom:semver 1.7.1
    string public constant version = "1.7.1";


    constructor() CrossDomainMessenger(Predeploys.L2_CROSS_DOMAIN_MESSENGER) {
        initialize({ _portal: PatexPortal(payable(0)) });
    }

    /// @notice Initializes the contract.
    /// @param _portal Address of the OptimismPortal contract on this network.
    function initialize(PatexPortal _portal) public reinitializer(10) {
        PORTAL = _portal;
        __CrossDomainMessenger_init();
    }

    /// @notice Getter for the OptimismPortal address.
    function portal() external view returns (address) {
        return address(PORTAL);
    }

    /// Patex: This function is modified from CrossDomainMessenger
    /// to enable discounted withdrawals on L1. The `msg.value`
    /// check is less strict and `msg.value` is used instead
    /// of `_value` in the following steps. Additionally, the
    /// `msg.value` is stored for failed messages so the correct
    /// value is used when the message is replayed.
    /// @inheritdoc CrossDomainMessenger
    function relayMessage(
        uint256 _nonce,
        address _sender,
        address _target,
        uint256 _value,
        uint256 _minGasLimit,
        bytes calldata _message
    )
        external
        payable
        override
    {
        (, uint16 version) = Encoding.decodeVersionedNonce(_nonce);
        require(version < 2, "CrossDomainMessenger: only version 0 or 1 messages are supported at this time");

        // If the message is version 0, then it's a migrated legacy withdrawal. We therefore need
        // to check that the legacy version of the message has not already been relayed.
        if (version == 0) {
            bytes32 oldHash = Hashing.hashCrossDomainMessageV0(_target, _sender, _message, _nonce);
            require(successfulMessages[oldHash] == false, "CrossDomainMessenger: legacy withdrawal already relayed");
        }

        // We use the v1 message hash as the unique identifier for the message because it commits
        // to the value and minimum gas limit of the message.
        bytes32 versionedHash =
            Hashing.hashCrossDomainMessageV1(_nonce, _sender, _target, _value, _minGasLimit, _message);

        uint256 _valueWithDiscount;
        if (_isOtherMessenger()) {
            // Patex: This check is modified to allow for discounted withdrawals.
            // If `_value` is non-zero, then the `msg.value` sent should be
            // equal to `_value` in the normal case, but between 0 and `_value`
            // if the withdrawal was discounted.
            assert(msg.value <= _value && (_value == 0 || msg.value > 0));

            // This property should always hold when the message is first submitted (as
            // opposed to being replayed).
            assert(!failedMessages[versionedHash]);

            _valueWithDiscount = msg.value;
        } else {
            require(msg.value == 0, "CrossDomainMessenger: value must be zero unless message is from a system address");

            require(failedMessages[versionedHash], "CrossDomainMessenger: message cannot be replayed");

            // Patex: Retrieve the potentially discounted value that was sent when the
            // message was first submitted.
            _valueWithDiscount = discountedValues[versionedHash];
        }

        require(
            _isUnsafeTarget(_target) == false, "CrossDomainMessenger: cannot send message to blocked system address"
        );

        require(successfulMessages[versionedHash] == false, "CrossDomainMessenger: message has already been relayed");

        // If there is not enough gas left to perform the external call and finish the execution,
        // return early and assign the message to the failedMessages mapping.
        // We are asserting that we have enough gas to:
        // 1. Call the target contract (_minGasLimit + RELAY_CALL_OVERHEAD + RELAY_GAS_CHECK_BUFFER)
        //   1.a. The RELAY_CALL_OVERHEAD is included in `hasMinGas`.
        // 2. Finish the execution after the external call (RELAY_RESERVED_GAS).
        //
        // If `xDomainMsgSender` is not the default L2 sender, this function
        // is being re-entered. This marks the message as failed to allow it to be replayed.
        if (
            !SafeCall.hasMinGas(_minGasLimit, RELAY_RESERVED_GAS + RELAY_GAS_CHECK_BUFFER)
                || xDomainMsgSender != Constants.DEFAULT_L2_SENDER
        ) {
            failedMessages[versionedHash] = true;
            emit FailedRelayedMessage(versionedHash);

            // Patex: Need to store the discounted value so it can be replayed with the correct value.
            discountedValues[versionedHash] = _valueWithDiscount;

            // Revert in this case if the transaction was triggered by the estimation address. This
            // should only be possible during gas estimation or we have bigger problems. Reverting
            // here will make the behavior of gas estimation change such that the gas limit
            // computed will be the amount required to relay the message, even if that amount is
            // greater than the minimum gas limit specified by the user.
            if (tx.origin == Constants.ESTIMATION_ADDRESS) {
                revert("CrossDomainMessenger: failed to relay message");
            }

            return;
        }

        xDomainMsgSender = _sender;
        bool success = SafeCall.call(_target, gasleft() - RELAY_RESERVED_GAS, _valueWithDiscount, _message);
        xDomainMsgSender = Constants.DEFAULT_L2_SENDER;

        if (success) {
            successfulMessages[versionedHash] = true;
            emit RelayedMessage(versionedHash);
        } else {
            failedMessages[versionedHash] = true;
            emit FailedRelayedMessage(versionedHash);

            // Patex: Need to store the discounted value so it can be replayed with the correct value.
            discountedValues[versionedHash] = _valueWithDiscount;

            // Revert in this case if the transaction was triggered by the estimation address. This
            // should only be possible during gas estimation or we have bigger problems. Reverting
            // here will make the behavior of gas estimation change such that the gas limit
            // computed will be the amount required to relay the message, even if that amount is
            // greater than the minimum gas limit specified by the user.
            if (tx.origin == Constants.ESTIMATION_ADDRESS) {
                revert("CrossDomainMessenger: failed to relay message");
            }
        }
    }

    /**
     * @inheritdoc CrossDomainMessenger
     */
    function _sendMessage(
        address _to,
        uint64 _gasLimit,
        uint256 _value,
        bytes memory _data
    ) internal override {
        PORTAL.depositTransaction{ value: _value }(_to, _value, _gasLimit, false, _data);
    }

    /**
     * @inheritdoc CrossDomainMessenger
     */
    function _isOtherMessenger() internal view override returns (bool) {
        return msg.sender == address(PORTAL) && PORTAL.l2Sender() == OTHER_MESSENGER;
    }

    /**
     * @inheritdoc CrossDomainMessenger
     */
    function _isUnsafeTarget(address _target) internal view override returns (bool) {
        return _target == address(this) || _target == address(PORTAL);
    }
}
