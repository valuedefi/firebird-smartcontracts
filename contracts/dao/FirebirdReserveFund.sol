// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IValueLiquidRouter.sol";
import "../interfaces/IValueLiquidFormula.sol";
import "../interfaces/IValueLiquidPair.sol";
import "../interfaces/IOneSwap.sol";
import "../interfaces/IRewardPool.sol";

interface IBurnabledERC20 {
    function burn(uint256) external;
}

interface IProtocolFeeRemover {
    function transfer(address _token, uint256 _value) external;

    function remove(address[] calldata pairs) external;
}

contract FirebirdReserveFund is OwnableUpgradeSafe {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public strategist;

    // flags
    bool public publicAllowed; // set to true to allow public to call rebalance()

    // price
    uint256 public hopePriceToSell; // to rebalance if price is high

    address public constant hope = address(0xd78C475133731CD54daDCb430F7aAE4F03C1E660);
    address public constant weth = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address public constant wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public constant usdc = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address public constant wbtc = address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);

    address public hopeWethPair = address(0xdd600F769a6BFe5Dac39f5DA23C18433E6d92CBa);
    address public hopeWmaticPair = address(0x5E9cd0861F927ADEccfEB2C0124879b277Dd66aC);
    address public wethUsdcPair = address(0x39D736D2b254eE30796f43Ec665143010b558F82);
    address public wmaticUsdcPair = address(0xCe2cB67b11ec0399E39AF20433927424f9033233);

    IProtocolFeeRemover public protocolFeeRemover = IProtocolFeeRemover(0xEf7E3401f70aE2e49E3D2af0A30d2978A059cd7b);
    address[] public protocolFeePairsToRemove;
    address[] public toCashoutTokenList;

    IUniswapV2Router public quickswapRouter = IUniswapV2Router(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    mapping(address => mapping(address => address[])) public quickswapPaths;

    IValueLiquidRouter public firebirdRouter = IValueLiquidRouter(0xF6fa9Ea1f64f1BBfA8d71f7f43fAF6D45520bfac); // FireBirdRouter
    IValueLiquidFormula public firebirdFormula = IValueLiquidFormula(0x7973b6961C8C5ca8026B9FB82332626e715ff8c7);
    mapping(address => mapping(address => address[])) public firebirdPaths;

    mapping(address => uint256) public maxAmountToTrade; // HOPE, WETH, WMATIC, USDC

    address public constant os3FBird = address(0x4a592De6899fF00fBC2c99d7af260B5E7F88D1B4);
    address public constant os3FBirdSwap = address(0x01C9475dBD36e46d1961572C8DE24b74616Bae9e);
    address public constant osIron3pool = address(0xC45c1087a6eF7A956af96B0fEED5a7c270f5C901);
    address public constant osIron3poolSwap = address(0x563E49a74fd6AB193751f6C616ce7Cf900D678E5);
    address public constant dai = address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    address public constant usdt = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

    /* =================== Added variables (need to keep orders for proxy to work) =================== */
    // ....

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event SwapToken(address inputToken, address outputToken, uint256 amount, uint256 amountReceived);
    event BurnToken(address token, uint256 amount);
    event CollectFeeFromProtocol(address[] pairs);
    event GetBackTokenFromProtocol(address token, uint256 amount);
    event ExecuteTransaction(address indexed target, uint256 value, string signature, bytes data);
    event OneSwapRemoveLiquidity(uint256 amount);
    event CollectOneSwapFees(uint256 timestampe);

    /* ========== Modifiers =============== */

    modifier onlyStrategist() {
        require(strategist == msg.sender || owner() == msg.sender, "!strategist");
        _;
    }

    modifier checkPublicAllow() {
        require(publicAllowed || strategist == msg.sender || owner() == msg.sender, "!operator nor !publicAllowed");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize() external initializer {
        OwnableUpgradeSafe.__Ownable_init();

        hopePriceToSell = 1000000; // >= 1 USDC

        hopeWethPair = address(0xdd600F769a6BFe5Dac39f5DA23C18433E6d92CBa);
        hopeWmaticPair = address(0x5E9cd0861F927ADEccfEB2C0124879b277Dd66aC);
        wethUsdcPair = address(0x39D736D2b254eE30796f43Ec665143010b558F82);
        wmaticUsdcPair = address(0xCe2cB67b11ec0399E39AF20433927424f9033233);

        protocolFeeRemover = IProtocolFeeRemover(0xEf7E3401f70aE2e49E3D2af0A30d2978A059cd7b);

        quickswapRouter = IUniswapV2Router(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
        firebirdRouter = IValueLiquidRouter(0xF6fa9Ea1f64f1BBfA8d71f7f43fAF6D45520bfac);
        firebirdFormula = IValueLiquidFormula(0x7973b6961C8C5ca8026B9FB82332626e715ff8c7);

        firebirdPaths[hope][weth] = [hopeWethPair];
        firebirdPaths[hope][wmatic] = [hopeWmaticPair];
        firebirdPaths[weth][usdc] = [wethUsdcPair];
        firebirdPaths[wmatic][usdc] = [wmaticUsdcPair];
        firebirdPaths[hope][usdc] = [hopeWethPair, wethUsdcPair];

        firebirdPaths[weth][hope] = [hopeWethPair];
        firebirdPaths[wmatic][hope] = [hopeWmaticPair];
        firebirdPaths[usdc][weth] = [wethUsdcPair];
        firebirdPaths[usdc][wmatic] = [wmaticUsdcPair];
        firebirdPaths[usdc][hope] = [wethUsdcPair, hopeWethPair];

        maxAmountToTrade[hope] = 20000 ether;
        maxAmountToTrade[weth] = 5 ether;
        maxAmountToTrade[wmatic] = 10000 ether;
        maxAmountToTrade[usdc] = 10000000000; // 10k

        toCashoutTokenList.push(weth);
        toCashoutTokenList.push(wmatic);
        toCashoutTokenList.push(weth);
        toCashoutTokenList.push(wbtc);

        firebirdPaths[wbtc][usdc] = [address(0x10F525CFbCe668815Da5142460af0fCfb5163C81), wethUsdcPair]; // WBTC -> WETH -> USDC

        strategist = msg.sender;
        publicAllowed = true;
    }

    function approveToken(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    function setStrategist(address _strategist) external onlyOwner {
        strategist = _strategist;
    }

    function setPublicAllowed(bool _publicAllowed) external onlyStrategist {
        publicAllowed = _publicAllowed;
    }

    function setQuickswapPath(address _input, address _output, address[] memory _path) external onlyStrategist {
        quickswapPaths[_input][_output] = _path;
    }

    function setFirebirdPaths(address _inputToken, address _outputToken, address[] memory _path) external onlyOwner {
        delete firebirdPaths[_inputToken][_outputToken];
        firebirdPaths[_inputToken][_outputToken] = _path;
    }

    function setFirebirdPathsToUsdcViaWeth(address _inputToken, address _pairWithWeth) external onlyOwner {
        delete firebirdPaths[_inputToken][usdc];
        firebirdPaths[_inputToken][usdc] = [_pairWithWeth, wethUsdcPair];
    }

    function setFirebirdPathsToUsdcViaWmatic(address _inputToken, address _pairWithWmatic) external onlyOwner {
        delete firebirdPaths[_inputToken][usdc];
        firebirdPaths[_inputToken][usdc] = [_pairWithWmatic, wethUsdcPair];
    }

    function setProtocolFeeRemover(IProtocolFeeRemover _protocolFeeRemover) external onlyOwner {
        protocolFeeRemover = _protocolFeeRemover;
    }

    function setProtocolFeePairsToRemove(address[] memory _protocolFeePairsToRemove) external onlyOwner {
        delete protocolFeePairsToRemove;
        protocolFeePairsToRemove = _protocolFeePairsToRemove;
    }

    function addProtocolFeePairs(address[] memory _protocolFeePairsToRemove) external onlyOwner {
        uint256 _length = _protocolFeePairsToRemove.length;
        for (uint256 i = 0; i < _length; i++) {
            addProtocolFeePair(_protocolFeePairsToRemove[i]);
        }
    }

    function addProtocolFeePair(address _pair) public onlyOwner {
        uint256 _length = protocolFeePairsToRemove.length;
        for (uint256 i = 0; i < _length; i++) {
            require(protocolFeePairsToRemove[i] != address(_pair), "duplicated pair");
        }
        protocolFeePairsToRemove.push(_pair);
    }

    function addTokenToCashout(address _token) external onlyOwner {
        uint256 _length = toCashoutTokenList.length;
        for (uint256 i = 0; i < _length; i++) {
            require(toCashoutTokenList[i] != address(_token), "duplicated token");
        }
        toCashoutTokenList.push(_token);
    }

    function removeTokenToCashout(address _token) external onlyOwner returns (bool) {
        uint256 _length = toCashoutTokenList.length;
        for (uint256 i = 0; i < _length; i++) {
            if (toCashoutTokenList[i] == _token) {
                if (i < _length - 1) {
                    toCashoutTokenList[i] = toCashoutTokenList[_length - 1];
                }
                delete toCashoutTokenList[_length - 1];
                toCashoutTokenList.pop();
                return true;
            }
        }
        revert("not found");
    }

    function grantFund(address _token, uint256 _amount, address _to) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }

    function setMaxAmountToTrade(address _token, uint256 _amount) external onlyStrategist {
        maxAmountToTrade[_token] = _amount;
    }

    function setHopePriceToSell(uint256 _hopePriceToSell) external onlyStrategist {
        require(_hopePriceToSell >= 500000 ether && _hopePriceToSell <= 8000000, "out of range"); // [0.5, 8] USDC
        hopePriceToSell = _hopePriceToSell;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function tokenBalances() public view returns (uint256 _hopeBal, uint256 _wethBal, uint256 _wmaticBal, uint256 _usdcBal) {
        _hopeBal = IERC20(hope).balanceOf(address(this));
        _wethBal = IERC20(weth).balanceOf(address(this));
        _wmaticBal = IERC20(wmatic).balanceOf(address(this));
        _usdcBal = IERC20(usdc).balanceOf(address(this));
    }

    function exchangeRate(address _inputToken, address _outputToken, uint256 _tokenAmount) public view returns (uint256) {
        uint256[] memory amounts = firebirdFormula.getAmountsOut(_inputToken, _outputToken, _tokenAmount, firebirdPaths[_inputToken][_outputToken]);
        return amounts[amounts.length - 1];
    }

    function getHopeToUsdcPrice() public view returns (uint256) {
        return exchangeRate(weth, usdc, exchangeRate(hope, weth, 1 ether));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function collectFeeFromProtocol() public checkPublicAllow {
        IProtocolFeeRemover(protocolFeeRemover).remove(protocolFeePairsToRemove);
        emit CollectFeeFromProtocol(protocolFeePairsToRemove);
    }

    function collectOneSwapFees() public checkPublicAllow {
        IOneSwap(os3FBirdSwap).withdrawAdminFees();
        IOneSwap(osIron3poolSwap).withdrawAdminFees();
        uint8 _daiIndex = IOneSwap(os3FBirdSwap).getTokenIndex(dai);
        uint8 _usdcIndex = IOneSwap(os3FBirdSwap).getTokenIndex(usdc);
        uint8 _usdtIndex = IOneSwap(os3FBirdSwap).getTokenIndex(usdt);
        uint256 _os3FBirdBal = IERC20(os3FBird).balanceOf(address(this));
        if (_os3FBirdBal > 0) {
            IERC20(os3FBird).safeIncreaseAllowance(os3FBirdSwap, _os3FBirdBal);
            IOneSwap(os3FBirdSwap).removeLiquidityOneToken(_os3FBirdBal, _usdcIndex, 1, now.add(60));
            emit OneSwapRemoveLiquidity(_os3FBirdBal);
        }
        uint256 _daiBal = IERC20(dai).balanceOf(address(this));
        if (_daiBal > 0) {
            IERC20(dai).safeIncreaseAllowance(os3FBirdSwap, _daiBal);
            uint256 _outputAmount = IOneSwap(os3FBirdSwap).swap(_daiIndex, _usdcIndex, _daiBal, 1, now.add(60));
            emit SwapToken(dai, usdc, _daiBal, _outputAmount);
        }
        uint256 _usdtBal = IERC20(usdt).balanceOf(address(this));
        if (_usdtBal > 0) {
            IERC20(usdt).safeIncreaseAllowance(os3FBirdSwap, _usdtBal);
            uint256 _outputAmount = IOneSwap(os3FBirdSwap).swap(_usdtIndex, _usdcIndex, _usdtBal, 1, now.add(60));
            emit SwapToken(usdt, usdc, _usdtBal, _outputAmount);
        }
        emit CollectOneSwapFees(now);
    }

    function cashoutHopeToUsdc() public checkPublicAllow {
        uint256 _hopePrice = getHopeToUsdcPrice();
        if (_hopePrice >= hopePriceToSell) {
            uint256 _sellingHope = IERC20(hope).balanceOf(address(this));
            (uint256 _hopeWethReserve, , uint256 _totalHopeReserve) = hopeLpReserves();
            uint256 _sellAmountToWethPool = _sellingHope.mul(_hopeWethReserve).div(_totalHopeReserve);
            uint256 _sellAmountToWmaticPool = _sellingHope.sub(_sellAmountToWethPool);
            _firebirdSwapToken(hope, weth, _sellAmountToWethPool);
            _firebirdSwapToken(hope, wmatic, _sellAmountToWmaticPool);
        }
    }

    function sellTokensToUsdc() public checkPublicAllow {
        uint256 _length = toCashoutTokenList.length;
        for (uint256 i = 0; i < _length; i++) {
            address _token = toCashoutTokenList[i];
            uint256 _tokenBal = IERC20(_token).balanceOf(address(this));
            if (_tokenBal > 0) {
                require(firebirdPaths[_token][usdc].length > 0, "No route to sell");
                _firebirdSwapToken(_token, usdc, _tokenBal);
            }
        }
    }

    function workForReserveFund() external checkPublicAllow {
        collectFeeFromProtocol();
        collectOneSwapFees();
        cashoutHopeToUsdc();
        sellTokensToUsdc();
    }

    function getBackTokenFromProtocol(address _token, uint256 _amount) public onlyStrategist {
        IProtocolFeeRemover(protocolFeeRemover).transfer(_token, _amount);
        emit GetBackTokenFromProtocol(_token, _amount);
    }

    function forceBurn(uint256 _hopeAmount) external onlyOwner {
        IBurnabledERC20(hope).burn(_hopeAmount);
    }

    function forceSell(address _buyingToken, uint256 _hopeAmount) public onlyStrategist {
        _firebirdSwapToken(hope, _buyingToken, _hopeAmount);
    }

    function forceSellToUsdc(uint256 _hopeAmount) external onlyStrategist {
        forceSell(usdc, _hopeAmount);
    }

    function forceBuy(address _sellingToken, uint256 _sellingAmount) external onlyStrategist {
        require(getHopeToUsdcPrice() <= hopePriceToSell, "current price is too high");
        _firebirdSwapToken(_sellingToken, hope, _sellingAmount);
    }

//    function trimNonCoreToken(address _sellingToken) public onlyStrategist {
//        require(_sellingToken != hope && _sellingToken != weth && _sellingToken != wmatic && _sellingToken != usdc, "core");
//        uint256 _bal = IERC20(_sellingToken).balanceOf(address(this));
//        if (_bal > 0) {
//            _firebirdSwapToken(_sellingToken, hope, _bal);
//        }
//    }

//    function quickswapSwapToken(address _inputToken, address _outputToken, uint256 _amount) external onlyStrategist {
//        _quickswapSwapToken(quickswapPaths[_inputToken][_outputToken], _inputToken, _outputToken, _amount);
//    }

    function quickswapAddLiquidity(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired) external onlyStrategist {
        _quickswapAddLiquidity(_tokenA, _tokenB, _amountADesired, _amountBDesired);
    }

//    function quickswapAddLiquidityMax(address _tokenA, address _tokenB) external onlyStrategist {
//        _quickswapAddLiquidity(_tokenA, _tokenB, IERC20(_tokenA).balanceOf(address(this)), IERC20(_tokenB).balanceOf(address(this)));
//    }

    function quickswapRemoveLiquidity(address _pair, uint256 _liquidity) external onlyStrategist {
        _quickswapRemoveLiquidity(_pair, _liquidity);
    }

//    function quickswapRemoveLiquidityMax(address _pair) external onlyStrategist {
//        _quickswapRemoveLiquidity(_pair, IERC20(_pair).balanceOf(address(this)));
//    }

    function firebirdSwapToken(address _inputToken, address _outputToken, uint256 _amount) external onlyStrategist {
        _firebirdSwapToken(_inputToken, _outputToken, _amount);
    }

    function firebirdAddLiquidity(address _pair, uint256 _amountADesired, uint256 _amountBDesired) external onlyStrategist {
        _firebirdAddLiquidity(_pair, _amountADesired, _amountBDesired);
    }

    function firebirdAddLiquidityMax(address _pair) external onlyStrategist {
        address _tokenA = IValueLiquidPair(_pair).token0();
        address _tokenB = IValueLiquidPair(_pair).token1();
        _firebirdAddLiquidity(_pair, IERC20(_tokenA).balanceOf(address(this)), IERC20(_tokenB).balanceOf(address(this)));
    }

    function firebirdRemoveLiquidity(address _pair, uint256 _liquidity) external onlyStrategist {
        _firebirdRemoveLiquidity(_pair, _liquidity);
    }

    function firebirdRemoveLiquidityMax(address _pair) external onlyStrategist {
        _firebirdRemoveLiquidity(_pair, IERC20(_pair).balanceOf(address(this)));
    }

    /* ========== FARMING ========== */

    function depositToPool(address _pool, uint256 _pid, address _lpAdd, uint256 _lpAmount) public onlyStrategist {
        IERC20(_lpAdd).safeIncreaseAllowance(_pool, _lpAmount);
        IRewardPool(_pool).deposit(_pid, _lpAmount);
    }

    function depositToPoolMax(address _pool, uint256 _pid, address _lpAdd) external onlyStrategist {
        uint256 _bal = IERC20(_lpAdd).balanceOf(address(this));
        require(_bal > 0, "no lp");
        depositToPool(_pool, _pid, _lpAdd, _bal);
    }

    function withdrawFromPool(address _pool, uint256 _pid, uint256 _lpAmount) public onlyStrategist {
        IRewardPool(_pool).withdraw(_pid, _lpAmount);
    }

    function withdrawFromPoolMax(address _pool, uint256 _pid) external onlyStrategist {
        uint256 _stakedAmount = stakeAmountFromPool(_pool, _pid);
        withdrawFromPool(_pool, _pid, _stakedAmount);
    }

    function claimFromPool(address _pool, uint256 _pid) public checkPublicAllow {
        IRewardPool(_pool).withdraw(_pid, 0);
    }

    function pendingFromPool(address _pool, uint256 _pid) external view returns (uint256) {
        return IRewardPool(_pool).pendingReward(_pid, address(this));
    }

    function stakeAmountFromPool(address _pool, uint256 _pid) public view returns (uint256 _stakedAmount) {
        (_stakedAmount,) = IRewardPool(_pool).userInfo(_pid, address(this));
    }

    /* ========== LIBRARIES ========== */

    function _quickswapSwapToken(address[] memory _path, address _inputToken, address _outputToken, uint256 _amount) internal {
        if (_amount == 0) return;
        uint256 _maxAmount = maxAmountToTrade[_inputToken];
        if (_maxAmount > 0 && _maxAmount < _amount) {
            _amount = _maxAmount;
        }
        if (_path.length <= 1) {
            _path = new address[](2);
            _path[0] = _inputToken;
            _path[1] = _outputToken;
        }
        IERC20(_inputToken).safeIncreaseAllowance(address(quickswapRouter), _amount);
        uint256[] memory amountReceiveds = IUniswapV2Router(quickswapRouter).swapExactTokensForTokens(_amount, 1, _path, address(this), now.add(60));
        emit SwapToken(_inputToken, _outputToken, _amount, amountReceiveds[amountReceiveds.length - 1]);
    }

    function _quickswapAddLiquidity(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired) internal {
        IERC20(_tokenA).safeIncreaseAllowance(address(quickswapRouter), _amountADesired);
        IERC20(_tokenB).safeIncreaseAllowance(address(quickswapRouter), _amountBDesired);
        IUniswapV2Router(quickswapRouter).addLiquidity(_tokenA, _tokenB, _amountADesired, _amountBDesired, 1, 1, address(this), now.add(60));
    }

    function _quickswapRemoveLiquidity(address _pair, uint256 _liquidity) internal {
        address _tokenA = IUniswapV2Pair(_pair).token0();
        address _tokenB = IUniswapV2Pair(_pair).token1();
        IERC20(_pair).safeIncreaseAllowance(address(quickswapRouter), _liquidity);
        IUniswapV2Router(quickswapRouter).removeLiquidity(_tokenA, _tokenB, _liquidity, 1, 1, address(this), now.add(60));
    }

    function _firebirdSwapToken(address _inputToken, address _outputToken, uint256 _amount) internal {
        if (_amount == 0) return;
        uint256 _maxAmount = maxAmountToTrade[_inputToken];
        if (_maxAmount > 0 && _maxAmount < _amount) {
            _amount = _maxAmount;
        }
        IERC20(_inputToken).safeIncreaseAllowance(address(firebirdRouter), _amount);
        uint256[] memory amountReceiveds = firebirdRouter.swapExactTokensForTokens(_inputToken, _outputToken, _amount, 1, firebirdPaths[_inputToken][_outputToken], address(this), now.add(60));
        emit SwapToken(_inputToken, _outputToken, _amount, amountReceiveds[amountReceiveds.length - 1]);
    }

    function _firebirdAddLiquidity(address _pair, uint256 _amountADesired, uint256 _amountBDesired) internal {
        address _tokenA = IValueLiquidPair(_pair).token0();
        address _tokenB = IValueLiquidPair(_pair).token1();
        IERC20(_tokenA).safeIncreaseAllowance(address(firebirdRouter), _amountADesired);
        IERC20(_tokenB).safeIncreaseAllowance(address(firebirdRouter), _amountBDesired);
        firebirdRouter.addLiquidity(_pair, _tokenA, _tokenB, _amountADesired, _amountBDesired, 0, 0, address(this), now.add(60));
    }

    function _firebirdRemoveLiquidity(address _pair, uint256 _liquidity) internal {
        IERC20(_pair).safeIncreaseAllowance(address(firebirdRouter), _liquidity);
        address _tokenA = IValueLiquidPair(_pair).token0();
        address _tokenB = IValueLiquidPair(_pair).token1();
        firebirdRouter.removeLiquidity(_pair, _tokenA, _tokenB, _liquidity, 1, 1, address(this), now.add(60));
    }

    function _getReserves(address tokenA, address tokenB, address pair) internal view returns (uint256 _reserveA, uint256 _reserveB) {
        address _token0 = IUniswapV2Pair(pair).token0();
        address _token1 = IUniswapV2Pair(pair).token1();
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (_token0 == tokenA) {
            if (_token1 == tokenB) {
                _reserveA = uint256(_reserve0);
                _reserveB = uint256(_reserve1);
            }
        } else if (_token0 == tokenB) {
            if (_token1 == tokenA) {
                _reserveA = uint256(_reserve1);
                _reserveB = uint256(_reserve0);
            }
        }
    }

    function hopeLpReserves() public view returns (uint256 _hopeWethReserve, uint256 _hopeWmaticReserve, uint256 _totalHopeReserve) {
        (_hopeWethReserve, ) = _getReserves(hope, weth, hopeWethPair);
        (_hopeWmaticReserve, ) = _getReserves(hope, usdc, hopeWmaticPair);
        _totalHopeReserve = _hopeWethReserve.add(_hopeWmaticReserve);
    }

    /* ========== EMERGENCY ========== */

    function renounceOwnership() public override onlyOwner {
        revert("Dangerous");
    }

    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data) public onlyOwner returns (bytes memory) {
        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, string("ReserveFund::executeTransaction: Transaction execution reverted."));

        emit ExecuteTransaction(target, value, signature, data);

        return returnData;
    }

    receive() external payable {}
}
