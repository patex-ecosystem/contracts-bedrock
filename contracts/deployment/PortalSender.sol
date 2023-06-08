// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { PatexPortal } from "../L1/PatexPortal.sol";

/**
 * @title PortalSender
 * @notice The PortalSender is a simple intermediate contract that will transfer the balance of the
 *         L1StandardBridge to the PatexPortal during the Bedrock migration.
 */
contract PortalSender {
    /**
     * @notice Address of the PatexPortal contract.
     */
    PatexPortal public immutable PORTAL;

    /**
     * @param _portal Address of the PatexPortal contract.
     */
    constructor(PatexPortal _portal) {
        PORTAL = _portal;
    }

    /**
     * @notice Sends balance of this contract to the PatexPortal.
     */
    function donate() public {
        PORTAL.donateETH{ value: address(this).balance }();
    }
}
