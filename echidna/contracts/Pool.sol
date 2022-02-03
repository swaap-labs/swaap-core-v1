// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.0;

import "./Const.sol";
import "./PoolToken.sol";
import "./Math.sol";

import "./Num.sol";
import "./structs/Struct.sol";


contract Pool is PoolToken {

    struct Record {
        bool bound;   // is token bound to pool
        uint256 index;   // private
        uint256 denorm;  // denormalized weight
        uint256 balance;
    }

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut,
        uint256         spread
    );

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _viewlock_() {
        require(!_mutex, "ERR_REENTRY");
        _;
    }

    bool private _mutex;

    address private _factory;    // Factory address to push token exitFee to
    address private _controller; // has CONTROL role
    bool private _publicSwap; // true if PUBLIC can call SWAP functions

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint256 private _swapFee;
    bool private _finalized;

    address[] private _tokens;
    mapping(address=>Record) private _records;
    uint256 private _totalWeight;

    constructor() {
        _controller = msg.sender;
        _factory = msg.sender;
        _swapFee = Const.MIN_FEE;
        _publicSwap = false;
        _finalized = false;
    }

    function isPublicSwap()
    external view
    returns (bool)
    {
        return _publicSwap;
    }

    function isFinalized()
    external view
    returns (bool)
    {
        return _finalized;
    }

    function isBound(address t)
    external view
    returns (bool)
    {
        return _records[t].bound;
    }

    function getNumTokens()
    external view
    returns (uint256)
    {
        return _tokens.length;
    }

    function getCurrentTokens()
    external view _viewlock_
    returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getFinalTokens()
    external view
    _viewlock_
    returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    function getDenormalizedWeight(address token)
    external view
    _viewlock_
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
    external view
    _viewlock_
    returns (uint256)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
    external view
    _viewlock_
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        uint256 denorm = _records[token].denorm;
        return Num.bdiv(denorm, _totalWeight);
    }

    function getBalance(address token)
    external view
    _viewlock_
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee()
    external view
    _viewlock_
    returns (uint256)
    {
        return _swapFee;
    }

    function getController()
    external view
    _viewlock_
    returns (address)
    {
        return _controller;
    }

    function setSwapFee(uint256 swapFee)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(swapFee >= Const.MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= Const.MAX_FEE, "ERR_MAX_FEE");
        require(swapFee >= 0, "ERR_FEE_SUP_0");
        require(swapFee <= Const.BONE, "ERR_FEE_INF_1");
        _swapFee = swapFee;
    }

    function setController(address manager)
    public
    _logs_
    _lock_
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(manager != address(0), "ERR_NULL_CONTROLLER");
        _controller = manager;
    }

    function setPublicSwap(bool public_)
    public
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _publicSwap = public_;
    }

    function finalize()
    public
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_tokens.length >= Const.MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");

        _finalized = true;
        _publicSwap = true;

        _mintPoolShare(Const.INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, Const.INIT_POOL_SUPPLY);
    }

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token)
    external
    _logs_
    _lock_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    function joinPool(uint256 poolAmountOut, uint256[] memory maxAmountsIn)
    public
    _logs_
    _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 ratio = Num.bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountIn = Num.bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance = _records[t].balance + tokenAmountIn;
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint256 poolAmountIn, uint256[] memory minAmountsOut)
    public
    _logs_
    _lock_
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 exitFee = Num.bmul(poolAmountIn, Const.EXIT_FEE);
        uint256 pAiAfterExitFee = poolAmountIn - exitFee;
        uint256 ratio = Num.bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = Num.bmul(ratio, bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance = _records[t].balance - tokenAmountOut;
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }

    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint256 amount)
    internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint256 amount)
    internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint256 amount)
    internal
    {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint256 amount)
    internal
    {
        _push(to, amount);
    }

    function _mintPoolShare(uint256 amount)
    internal
    {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount)
    internal
    {
        _burn(amount);
    }

    struct Price {
        IAggregatorV3 oracle;
        uint256 initialPrice;
    }

    event LOG_PRICE(
        address indexed token,
        address indexed oracle,
        uint256 indexed value
    ) anonymous;

    mapping(address=>Price) private _prices;

    uint256 dynamicCoverageFeesZ = Const.BASE_Z;
    uint256 dynamicCoverageFeesHorizon = Const.BASE_HORIZON;

    uint256 priceStatisticsLookbackInRound = Const.BASE_LOOKBACK_IN_ROUND;
    uint256 priceStatisticsLookbackInSec = Const.BASE_LOOKBACK_IN_SEC;

    function setDynamicCoverageFeesZ(uint256 _dynamicCoverageFeesZ)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_dynamicCoverageFeesZ >= 0, "ERR_MIN_Z");
        require(_dynamicCoverageFeesZ <= Const.MAX_Z, "ERR_MAX_Z");
        dynamicCoverageFeesZ = _dynamicCoverageFeesZ;
    }

    function setDynamicCoverageFeesHorizon(uint256 _dynamicCoverageFeesHorizon)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_dynamicCoverageFeesHorizon >= Const.MIN_HORIZON, "ERR_MIN_HORIZON");
        require(_dynamicCoverageFeesHorizon <= Const.MAX_HORIZON, "ERR_MAX_HORIZON");
        dynamicCoverageFeesHorizon = _dynamicCoverageFeesHorizon;
    }

    function setPriceStatisticsLookbackInRound(uint256 _priceStatisticsLookbackInRound)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_priceStatisticsLookbackInRound >= Const.MIN_LOOKBACK_IN_ROUND, "ERR_MIN_LB_PERIODS");
        require(_priceStatisticsLookbackInRound <= Const.MAX_LOOKBACK_IN_ROUND, "ERR_MAX_LB_PERIODS");
        priceStatisticsLookbackInRound = _priceStatisticsLookbackInRound;
    }

    function setPriceStatisticsLookbackInSec(uint256 _priceStatisticsLookbackInSec)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_priceStatisticsLookbackInSec >= Const.MIN_LOOKBACK_IN_SEC, "ERR_MIN_LB_SECS");
        require(_priceStatisticsLookbackInSec <= Const.MAX_LOOKBACK_IN_SEC, "ERR_MAX_LB_SECS");
        priceStatisticsLookbackInSec = _priceStatisticsLookbackInSec;
    }

    function getCoverageParameters()
    external view
    _viewlock_
    returns (uint256, uint256, uint256, uint256)
    {
        return (
            dynamicCoverageFeesZ,
            dynamicCoverageFeesHorizon,
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec
        );
    }

    function getTokenPriceDecimals(address token)
    external view
    _viewlock_
    returns (uint8)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _getTokenPriceDecimals(_prices[token].oracle);
    }

    function getTokenOraclePrice(address token)
    external view
    _viewlock_
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _getTokenCurrentPrice(_prices[token].oracle);
    }

    function getTokenOracleInitialPrice(address token)
    external view
    _viewlock_
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _prices[token].initialPrice;
    }

    function getTokenPriceOracle(address token)
    external view
    _viewlock_
    returns (address)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return address(_prices[token].oracle);
    }

    function getDenormalizedWeightMMM(address token)
    external view
    returns (uint256)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _getAdjustedTokenWeight(token);
    }

    function getTotalDenormalizedWeightMMM()
    external view
    returns (uint256)
    {
        return _getTotalDenormalizedWeightMMM();
    }

    function getNormalizedWeightMMM(address token)
    external view
    returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _getNormalizedWeightMMM(token);
    }

    function _getTotalDenormalizedWeightMMM()
    internal view
    _viewlock_
    returns (uint256)
    {
        uint256 _totalWeightMMM;
        for (uint256 i = 0; i < _tokens.length; i++) {
            _totalWeightMMM += _getAdjustedTokenWeight(_tokens[i]);
        }
        return _totalWeightMMM;
    }

    function _getNormalizedWeightMMM(address token)
    internal view
    _viewlock_
    returns (uint256)
    {

        return Num.bdiv(_getAdjustedTokenWeight(token), _getTotalDenormalizedWeightMMM());
    }

    function bindMMM(address token, uint256 balance, uint256 denorm, address _priceFeedAddress)
    public
    _logs_
        // _lock_  Bind does not lock because it jumps to `rebind`, which does
    {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(_tokens.length < Const.MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        _records[token] = Record(
            {
                bound: true,
                index: _tokens.length,
                denorm: 0,    // balance and denorm will be validated
                balance: 0   // and set by `rebind`
            }
        );
        _tokens.push(token);
        rebindMMM(token, balance, denorm, _priceFeedAddress);
    }

    function rebindMMM(address token, uint256 balance, uint256 denorm, address _priceFeedAddress)
    public
    _logs_
    _lock_
    {

        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(denorm >= Const.MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= Const.MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= Const.MIN_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the denorm and totalWeight
        uint256 oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = _totalWeight + (denorm - oldWeight);
            require(_totalWeight <= Const.MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        } else if (denorm < oldWeight) {
            _totalWeight = (_totalWeight - oldWeight) + denorm;
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint256 oldBalance = _records[token].balance;
        _records[token].balance = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, balance - oldBalance);
        } else if (balance < oldBalance) {
            // In this case liquidity is being withdrawn, so charge EXIT_FEE
            uint256 tokenBalanceWithdrawn = oldBalance - balance;
            uint256 tokenExitFee = Num.bmul(tokenBalanceWithdrawn, Const.EXIT_FEE);
            _pushUnderlying(token, msg.sender, tokenBalanceWithdrawn - tokenExitFee);
            _pushUnderlying(token, _factory, tokenExitFee);
        }

        // Add token price
        _prices[token] = Price(
            {
                oracle: IAggregatorV3(_priceFeedAddress),
                initialPrice: 0 // set right below
            }
        );
        _prices[token].initialPrice = _getTokenCurrentPrice(_prices[token].oracle);
        emit LOG_PRICE(token, address(_prices[token].oracle), _prices[token].initialPrice);
    }

    function unbindMMM(address token)
    public
    _logs_
    _lock_
    {

        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        uint256 tokenBalance = _records[token].balance;
        uint256 tokenExitFee = Num.bmul(tokenBalance, Const.EXIT_FEE);

        _totalWeight = _totalWeight - _records[token].denorm;

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint256 index = _records[token].index;
        uint256 last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        _records[token] = Record(
            {
                bound: false,
                index: 0,
                denorm: 0,
                balance: 0
            }
        );
        _prices[token] = Price({oracle: IAggregatorV3(address(0)), initialPrice: 0});

        _pushUnderlying(token, msg.sender, tokenBalance - tokenExitFee);
        _pushUnderlying(token, _factory, tokenExitFee);

    }

    function _getSpotPriceMMMWithTimestamp(address tokenIn, address tokenOut, uint256 swapFee, uint256 timestamp)
    internal view _viewlock_
    returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec,
            timestamp
        );

        return Math.calcSpotPriceMMM(
            tokenGlobalIn.info, tokenGlobalIn.latestRound,
            tokenGlobalOut.info, tokenGlobalOut.latestRound,
            getTokenOutPriceInTokenInTerms(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound),
            swapFee, gbmParameters,
            hpParameters
        );
    }

    function getSpotPriceMMM(address tokenIn, address tokenOut)
    external view
    returns (uint256 spotPrice)
    {
        return _getSpotPriceMMMWithTimestamp(tokenIn, tokenOut, _swapFee, block.timestamp);
    }

    function getSpotPriceSansFeeMMM(address tokenIn, address tokenOut)
    external view
    returns (uint256 spotPrice)
    {
        return _getSpotPriceMMMWithTimestamp(tokenIn, tokenOut, 0, block.timestamp);
    }

    function swapExactAmountInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    public
    returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        return _swapExactAmountInMMMWithTimestamp(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            maxPrice,
            block.timestamp
        );
    }

    function _swapExactAmountInMMMWithTimestamp(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice,
        uint256 timestamp
    )
    internal
    _logs_
    _lock_
    returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {

        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        uint256 spotPriceBefore = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        Struct.SwapResult memory swapResult = _getAmountOutGivenInMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountIn,
            timestamp
        );
        require(swapResult.amount >= minAmountOut, "ERR_LIMIT_OUT");

        _records[address(tokenIn)].balance = tokenGlobalIn.info.balance + tokenAmountIn;
        _records[address(tokenOut)].balance = tokenGlobalOut.info.balance - swapResult.amount;

        spotPriceAfter = Math.calcSpotPrice(
            _records[address(tokenIn)].balance,
            tokenGlobalIn.info.weight,
            _records[address(tokenOut)].balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= Num.bdiv(tokenAmountIn, swapResult.amount), "ERR_MATH_APPROX");

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, swapResult.amount, swapResult.spread);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, swapResult.amount);

        return (tokenAmountOut = swapResult.amount, spotPriceAfter = spotPriceAfter);
    }

    function getAmountOutGivenInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut
    )
    public view
    returns (uint256 tokenAmountOut)
    {

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        Struct.SwapResult memory swapResult = _getAmountOutGivenInMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountIn,
            block.timestamp
        );

        return tokenAmountOut = swapResult.amount;
    }

    function _getAmountOutGivenInMMMWithTimestamp(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 tokenAmountIn,
        uint256 timestamp
    )
    internal view
    returns (Struct.SwapResult memory)
    {

        require(tokenAmountIn <= Num.bmul(_records[tokenGlobalIn.token].balance, Const.MAX_IN_RATIO), "ERR_MAX_IN_RATIO");
        require(tokenAmountIn <= _records[tokenGlobalIn.token].balance, "ERR_INSUFFICIENT_RESERVE");

        Struct.SwapParameters memory swapParameters = Struct.SwapParameters(tokenAmountIn, _swapFee);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec,
            timestamp
        );

        return Math.calcOutGivenInMMM(
            tokenGlobalIn.info,
            tokenGlobalIn.latestRound,
            tokenGlobalOut.info,
            tokenGlobalOut.latestRound,
            getTokenOutPriceInTokenInTerms(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound),
            swapParameters,
            gbmParameters,
            hpParameters
        );

    }

    function _getAdjustedTokenWeight(address token)
    internal view returns (uint256) {
        // we adjust the token's target weight (in value) based on its appreciation since the inception of the pool.
        return Num.bmul(
            _records[token].denorm,
            Num.bdiv(
                _getTokenCurrentPrice(_prices[token].oracle),
                _prices[token].initialPrice
            )
        );
    }

    function getTokenLatestInfo(address token)
    internal view returns (Struct.TokenGlobal memory tokenGlobal) {
        Record memory record = _records[token];
        Price memory price = _prices[token];
        (uint80 latestRoundId, int256 latestPrice, , uint256 latestTimestamp,) = price.oracle.latestRoundData();
        Struct.TokenRecord memory info = Struct.TokenRecord(
            record.balance,
            // we adjust the token's target weight (in value) based on its appreciation since the inception of the pool.
            Num.bmul(
                record.denorm,
                Num.bdiv(
                    _toUInt256Unsafe(latestPrice),
                    price.initialPrice
                )
            )
        );
        Struct.LatestRound memory latestRound = Struct.LatestRound(address(price.oracle), latestRoundId, latestPrice, latestTimestamp);
        return (
            tokenGlobal = Struct.TokenGlobal(
                token,
                info,
                latestRound
            )
        );
    }

    function _getTokenCurrentPrice(IAggregatorV3 priceFeed) internal view returns (uint256) {
        (, int256 price, , ,) = priceFeed.latestRoundData();
        return _toUInt256Unsafe(price);
    }

    function _getTokenPriceDecimals(IAggregatorV3 priceFeed) internal view returns (uint8) {
        return priceFeed.decimals();
    }

    function _toUInt256Unsafe(int256 value) internal pure returns (uint256) {
        if (value <= 0) {
            return uint256(0);
        }
        return uint256(value);
    }

    function getTokenOutPriceInTokenInTerms(
        Struct.LatestRound memory tokenIn, Struct.LatestRound memory tokenOut
    )
    internal
    view
    returns (uint256) {
        uint8 decimalIn = IAggregatorV3(tokenIn.oracle).decimals();
        uint8 decimalOut = IAggregatorV3(tokenOut.oracle).decimals();
        uint256 rawDiv = Num.bdiv(_toUInt256Unsafe(tokenOut.price), _toUInt256Unsafe(tokenIn.price));
        if (decimalIn == decimalOut) {
            return rawDiv;
        } else if (decimalIn > decimalOut) {
            return Num.bmul(
                rawDiv,
                10**(decimalIn - decimalOut)*Const.BONE
            );
        } else {
            return Num.bdiv(
                rawDiv,
                10**(decimalOut - decimalIn)*Const.BONE
            );
        }
    }

}