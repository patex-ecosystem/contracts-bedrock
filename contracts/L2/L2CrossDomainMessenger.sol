// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { AddressAliasHelper } from "../vendor/AddressAliasHelper.sol";
import { Predeploys } from "../libraries/Predeploys.sol";
import { CrossDomainMessenger } from "../universal/CrossDomainMessenger.sol";
import { ISemver } from "../universal/ISemver.sol";
import { L2ToL1MessagePasser } from "./L2ToL1MessagePasser.sol";
import { Postdeploys } from "../L2/Postdeploys.sol";
import { Patex, YieldMode, GasMode } from "../L2/Patex.sol";
import { Constants } from "../libraries/Constants.sol";

/**
 * @custom:proxied
 * @custom:predeploy 0x4200000000000000000000000000000000000007
 * @title L2CrossDomainMessenger
 * @notice The L2CrossDomainMessenger is a high-level interface for message passing between L1 and
 *         L2 on the L2 side. Users are generally encouraged to use this contract instead of lower
 *         level message passing contracts.
 */
contract L2CrossDomainMessenger is CrossDomainMessenger, ISemver {

    Postdeploys public postdeploys;

    /// @custom:semver 1.7.0
    string public constant version = "1.7.0";
    /**
     * @custom:semver 1.1.0
     *
     * @param _l1CrossDomainMessenger Address of the L1CrossDomainMessenger contract.
     */
    constructor(address _l1CrossDomainMessenger)
        CrossDomainMessenger(_l1CrossDomainMessenger)
    {
        _disableInitializers();
    }

    /**
     * @notice Initializer.
     */
    function initialize(Postdeploys _postdeploys) public reinitializer(10) {
        __CrossDomainMessenger_init();

        postdeploys = _postdeploys;
        Patex(Postdeploys(postdeploys).PATEX()).configureContract(
            address(this),
            YieldMode.VOID,
            GasMode.VOID,
            address(0xdead) /// don't set a governor
        );
    }

    /**
     * @custom:legacy
     * @notice Legacy getter for the remote messenger. Use otherMessenger going forward.
     *
     * @return Address of the L1CrossDomainMessenger contract.
     */
    function l1CrossDomainMessenger() public view returns (address) {
        return OTHER_MESSENGER;
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
        L2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{
            value: _value
        }(_to, _gasLimit, _data);
    }

    /**
     * @inheritdoc CrossDomainMessenger
     */
    function _isOtherMessenger() internal view override returns (bool) {
        return AddressAliasHelper.undoL1ToL2Alias(msg.sender) == OTHER_MESSENGER;
    }

    /**
     * @inheritdoc CrossDomainMessenger
     */
    function _isUnsafeTarget(address _target) internal view override returns (bool) {
        return _target == address(this) || _target == address(Predeploys.L2_TO_L1_MESSAGE_PASSER) || _target == address(Postdeploys(postdeploys).PATEX());
    }
}
