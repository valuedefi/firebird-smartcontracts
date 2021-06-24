// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IOneSwap {
    // pool data view functions
    function getA() external view returns (uint256);

    function getToken(uint8 index) external view returns (address);

    function getTokenIndex(address tokenAddress) external view returns (uint8);

    function getTokenBalance(uint8 index) external view returns (uint256);

    function getTokenLength() external view returns (uint256);

    function getVirtualPrice() external view returns (uint256);

    function swapStorage()
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        address
    );

    // min return calculation functions
    function calculateSwap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx
    ) external view returns (uint256);

    function calculateRemoveLiquidity(uint256 amount) external view returns (uint256[] memory);

    function calculateRemoveLiquidityOneToken(uint256 tokenAmount, uint8 tokenIndex) external view returns (uint256 availableTokenAmount);

    // state modifying functions
    function swap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256);

    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);

    function removeLiquidity(
        uint256 amount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory);

    function removeLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256);

    function removeLiquidityImbalance(
        uint256[] calldata amounts,
        uint256 maxBurnAmount,
        uint256 deadline
    ) external returns (uint256);

    // withdraw fee update function
    function updateUserWithdrawFee(address recipient, uint256 transferAmount) external;

    function calculateRemoveLiquidity(address account, uint256 amount) external view returns (uint256[] memory);

    function calculateTokenAmount(
        address account,
        uint256[] calldata amounts,
        bool deposit
    ) external view returns (uint256);

    function calculateRemoveLiquidityOneToken(
        address account,
        uint256 tokenAmount,
        uint8 tokenIndex
    ) external view returns (uint256 availableTokenAmount);

    function withdrawAdminFees() external;
}
