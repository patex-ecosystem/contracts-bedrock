// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { YieldManager } from "./YieldManager.sol";

interface IUSDT {
    function approve(address spender, uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
}

interface IDssPsm {
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
    function gemJoin() external view returns (address);
}

interface ICurve3Pool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

/// @title USDConversions
/// @notice Stateless helper module for converting between USD tokens (DAI/USDC/USDT).
///
///         DAI and USDC are converted 1-to-1 using Maker's Peg Stability Mechanism.
///         All other tokens conversions are completed through Curve's 3Pool.
library USDConversions {
    uint256 constant WAD_DECIMALS = 18;
    uint256 constant USD_DECIMALS = 6;
    int128 constant DAI_INDEX = 0;
    int128 constant USDC_INDEX = 1;
    int128 constant USDT_INDEX = 2;

    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUSDT constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IDssPsm constant PSM = IDssPsm(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);
    ICurve3Pool constant CURVE_3POOL = ICurve3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    /// @notice immutable address of PSM's GemJoin contract
    address constant GEM_JOIN = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;

    error InsufficientBalance();
    error MinimumAmountNotMet();
    error IncorrectInputAmountUsed();
    error UnsupportedToken();
    error InvalidExtraData();
    error InvalidTokenIndex();

    /// @notice Initializer
    function _init() internal {
        USDC.approve(address(CURVE_3POOL), type(uint256).max);
        USDC.approve(GEM_JOIN, type(uint256).max);
        USDT.approve(address(CURVE_3POOL), type(uint256).max);
        DAI.approve(address(CURVE_3POOL), type(uint256).max);
        DAI.approve(GEM_JOIN, type(uint256).max);
        DAI.approve(address(PSM), type(uint256).max);
    }

    /// @notice Convert between the 3 stablecoin tokens using Curve's 3Pool and Maker's
    ///         Peg Stability Mechanism.
    /// @param inputToken         Input token index.
    /// @param outputToken        Output token index.
    /// @param inputAmountWad     Input amount in WAD.
    /// @param minOutputAmountWad Minimum amount of output token accepted in WAD.
    /// @return amountReceived Amount of output token received in the token's
    ///         decimal representation.
    function _convert(int128 inputToken, int128 outputToken, uint256 inputAmountWad, uint256 minOutputAmountWad) internal returns (uint256 amountReceived) {
        require(inputToken >= 0 && inputToken < 3 && outputToken >= 0 && outputToken < 3);
        require(inputToken != outputToken);
        if (inputAmountWad > 0) {
            uint256 inputAmount = _convertDecimals(inputAmountWad, inputToken);
            uint256 minOutputAmount = _convertDecimals(minOutputAmountWad, outputToken);
            if (_tokenBalance(inputToken) < inputAmount) {
                revert InsufficientBalance();
            }
            uint256 beforeBalance = _tokenBalance(outputToken);
            if (inputToken == USDC_INDEX && outputToken == DAI_INDEX) {
                PSM.sellGem(address(this), inputAmount);
            } else if (inputToken == DAI_INDEX && outputToken == USDC_INDEX) {
                uint256 beforeInputBalance = _tokenBalance(inputToken);
                PSM.buyGem(address(this), _wadToUSD(minOutputAmountWad)); // buyGem expects the input amount in USDC
                uint256 amountSent = beforeInputBalance - _tokenBalance(inputToken);
                if (amountSent != inputAmountWad) {
                    revert IncorrectInputAmountUsed();
                }
            } else {
                CURVE_3POOL.exchange(
                    inputToken,
                    outputToken,
                    inputAmount,
                    minOutputAmount
                );
            }
            amountReceived = _tokenBalance(outputToken) - beforeBalance;
            if (amountReceived < minOutputAmount) {
                revert MinimumAmountNotMet();
            }
        }
    }

    /// @notice Convert between supported token pairs, reverting if not supported.
    /// @param inputTokenAddress  Address of the input token.
    /// @param outputTokenAddress Address of the output token.
    /// @param inputAmountWad     Amount of input token to convert in WAD.
    /// @param _extraData         Extra data containing the minimum amount of output token to receive in WAD.
    /// @return amountReceived Amount of output token received in WAD.
    function _convertTo(
        address inputTokenAddress,
        address outputTokenAddress,
        uint256 inputAmountWad,
        bytes memory _extraData
    ) internal returns (uint256 amountReceived) {
        if (inputTokenAddress == outputTokenAddress) {
            return inputAmountWad;
        }

        if (outputTokenAddress == address(DAI)) {
            return _convertToDAI(inputTokenAddress, inputAmountWad, _extraData);
        } else {
            revert UnsupportedToken();
        }
    }

    /// @notice Convert USDC, USDT, and DAI to DAI. If the input token is DAI,
    ///         the input amount is returned without conversion.
    /// @param inputTokenAddress Address of the input token.
    /// @param inputAmountWad    Amount of input token to convert in WAD.
    /// @param _extraData        Extra data containing the minimum amount of USDB to be minted in WAD.
    ///                          Only needed for USDC and USDT. The expected format is: (uint256 minOutputAmountWad).
    /// @return amountReceived Amount of DAI received.
    function _convertToDAI(address inputTokenAddress, uint256 inputAmountWad, bytes memory _extraData) internal returns (uint256 amountReceived) {
        if (inputTokenAddress == address(DAI)) {
            return inputAmountWad;
        }

        if (_extraData.length != 32) {
            revert InvalidExtraData();
        }

        uint256 minOutputAmountWad = abi.decode(_extraData, (uint256));

        if (inputTokenAddress == address(USDC)) {
            return USDConversions._convert(USDC_INDEX, DAI_INDEX, inputAmountWad, minOutputAmountWad);
        } else if (inputTokenAddress == address(USDT)) {
            return USDConversions._convert(USDT_INDEX, DAI_INDEX, inputAmountWad, minOutputAmountWad);
        } else {
            revert UnsupportedToken();
        }
    }

    /// @notice Get the token address from the Curve token index.
    /// @param index Curve token index.
    /// @return Address of the token.
    function _token(int128 index) private pure returns (address) {
        if (index == USDC_INDEX) {
            return address(USDC);
        } else if (index == USDT_INDEX) {
            return address(USDT);
        } else if (index == DAI_INDEX) {
            return address(DAI);
        } else {
            revert InvalidTokenIndex();
        }
    }

    /// @notice Get the contract's token balance from the Curve token index.
    /// @param index Curve token index.
    /// @return Token balance.
    function _tokenBalance(int128 index) internal view returns (uint256) {
        if (_token(index) == YieldManager(address(this)).TOKEN()) {
            return YieldManager(address(this)).availableBalance();
        } else {
            return IERC20(_token(index)).balanceOf(address(this));
        }
    }

    /// @notice Convert WAD representation to the token's native decimal representation.
    ///         USDT and USDC are both 6 decimals and are converted.
    /// @param wad   Amount in WAD.
    /// @param index Curve 3Pool index of the token.
    /// @return result Amount in native decimals representation.
    function _convertDecimals(uint256 wad, int128 index) internal pure returns (uint256 result) {
        if (index == USDT_INDEX || index == USDC_INDEX) {
            result = _wadToUSD(wad);
        } else {
            result = wad;
        }
    }

    /// @notice Convert value in WAD (18 decimals) to USD (6 decimals).
    /// @param wad Amount to convert in WAD.
    /// @return Amount in USD.
    function _wadToUSD(uint256 wad) internal pure returns (uint256) {
        return _convertDecimals(wad, WAD_DECIMALS, USD_DECIMALS);
    }

    /// @notice Convert value in USD (6 decimals) to WAD (18 decimals).
    /// @param usd Amount to convert in USD.
    /// @return Amount in WAD.
    function _usdToWad(uint256 usd) internal pure returns (uint256) {
        return _convertDecimals(usd, USD_DECIMALS, WAD_DECIMALS);
    }

    /// @notice Convert value to desired output decimals representation.
    /// @param input          Input amount.
    /// @param inputDecimals  Number of decimals in the input.
    /// @param outputDecimals Desired number of decimals in the output.
    /// @return `input` in `outputDecimals`.
    function _convertDecimals(uint256 input, uint256 inputDecimals, uint256 outputDecimals) internal pure returns (uint256) {
        if (inputDecimals > outputDecimals) {
            return input / (10 ** (inputDecimals - outputDecimals));
        } else {
            return input * (10 ** (outputDecimals - inputDecimals));
        }
    }
}
