// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

interface IDelegateCalls {
    function payInsurancePremium(uint256) external;
    function withdrawFromInsurance(uint256) external;
    function stake(uint256) external;
    function unstake(uint256) external returns (uint256, uint256);
    function preCommitYieldReportDelegateCallHook() external;
}

abstract contract DelegateCalls {
    function _delegatecall_payInsurancePremium(address provider, uint256 arg) internal {
        (bool success,) = provider.delegatecall(
            abi.encodeCall(IDelegateCalls.payInsurancePremium, (arg))
        );
        require(success, "delegatecall failed");
    }

    function _delegatecall_withdrawFromInsurance(address provider, uint256 arg) internal {
        (bool success,) = provider.delegatecall(
            abi.encodeCall(IDelegateCalls.withdrawFromInsurance, (arg))
        );
        require(success, "delegatecall failed");
    }

    function _delegatecall_stake(address provider, uint256 arg) internal {
        (bool success,) = provider.delegatecall(
            abi.encodeCall(IDelegateCalls.stake, (arg))
        );
        require(success, "delegatecall failed");
    }

    function _delegatecall_unstake(address provider, uint256 arg) internal returns (uint256, uint256) {
        (bool success, bytes memory res) = provider.delegatecall(
            abi.encodeCall(IDelegateCalls.unstake, (arg))
        );
        require(success, "delegatecall failed");
        return abi.decode(res, (uint256, uint256));
    }

    function _delegatecall_preCommitYieldReportDelegateCallHook(address provider) internal {
        (bool success,) = provider.delegatecall(
            abi.encodeCall(IDelegateCalls.preCommitYieldReportDelegateCallHook, ())
        );
        require(success, "delegatecall failed");
    }
}
