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

pragma solidity =0.8.12;

import "./Const.sol";
import "./PoolToken.sol";
import "./Math.sol";

import "./Num.sol";
import "./structs/Struct.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IPausedFactory.sol";

import "./ChainlinkUtils.sol";

contract Pool is PoolToken {

    using SafeERC20 for IERC20; 

    struct Record {
        bool bound;   // is token bound to pool
        uint8 index;   // private
        uint80 denorm;  // denormalized weight
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

    event LOG_NEW_CONTROLLER(
        address indexed from,
        address indexed to
    );

    // putting modifier logic in functions enables contract size optimization
    function _emitLog() private {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
    }

    modifier _logs_() {
        _emitLog();
        _;
    }

    function _lock() private {
        require(!_mutex, "0");
        _mutex = true;
    }

    function _unlock() private {
        _mutex = false;
    }

    modifier _lock_() {
        _lock();
        _;
        _unlock();
    }

    modifier _viewlock_() {
        require(!_mutex, "0");
        _;
    }

    function _whenNotPaused() private view {
        IPausedFactory(_factory).whenNotPaused();
    }

    modifier _whenNotPaused_() {
        _whenNotPaused();
        _;
    }

    address[] private _tokens;
    mapping(address=>Record) private _records;

    bool private _mutex;
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    bool private _publicSwap; // true if PUBLIC can call SWAP functions
    uint80 private _totalWeight;
    address private _controller; // has CONTROL role
    address private _pendingController;
    
    bool private _finalized;
    address immutable private _factory;    // Factory address to push token exitFee to
    uint8 private priceStatisticsLookbackInRound;
    uint64 private dynamicCoverageFeesZ;

    // `setSwapFee` and `finalize` require CONTROL
    uint256 private _swapFee;
        
    mapping(address=>Price) private _prices;

    uint256 private dynamicCoverageFeesHorizon;
    uint256 private priceStatisticsLookbackInSec;

    constructor() {
        _controller = msg.sender;
        _factory = msg.sender;
        _swapFee = Const.MIN_FEE;
        priceStatisticsLookbackInRound = Const.BASE_LOOKBACK_IN_ROUND;
        priceStatisticsLookbackInSec = Const.BASE_LOOKBACK_IN_SEC;
        dynamicCoverageFeesZ = Const.BASE_Z;
        dynamicCoverageFeesHorizon = Const.BASE_HORIZON;
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

    function getTokens()
    external view
    _viewlock_
    returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getDenormalizedWeight(address token)
    external view
    returns (uint256)
    {
        require(_records[token].bound, "2");
        return _records[token].denorm;
    }

    function getBalance(address token)
    external view
    returns (uint256)
    {
        require(_records[token].bound, "2");
        return _records[token].balance;
    }

    function getSwapFee()
    external view
    returns (uint256)
    {
        return _swapFee;
    }

    function getController()
    external view
    returns (address)
    {
        return _controller;
    }

    function setSwapFee(uint256 swapFee)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        require(swapFee >= Const.MIN_FEE, "14");
        require(swapFee <= Const.MAX_FEE, "15");
        _swapFee = swapFee;
    }

    /**
    * @notice Allows a controller to transfer ownership to a new address
    * @dev It is recommended to use transferOwnership/acceptOwnership logic for safer transfers
    * This function is useful when creating pools using a proxy contract
    */    
    function setController(address manager)
    external
    _lock_
    {
        require(msg.sender == _controller, "3");
        require(manager != address(0), "13");
        _controller = manager;
        _pendingController = address(0);
        emit LOG_NEW_CONTROLLER(msg.sender, manager);
    }
    
    /**
    * @notice Allows a controller to begin transferring ownership to a new address,
    * pending.
    */
    function transferOwnership(address _to)
    external
    _logs_
    {
        require(msg.sender == _controller, "3");
        _pendingController = _to;
    }

    /**
    * @notice Allows a controller transfer to be completed by the recipient.
    */
    function acceptOwnership()
    external
    {
        require(msg.sender == _pendingController, "47");

        address oldController = _controller;
        _controller = msg.sender;
        _pendingController = address(0);

        emit LOG_NEW_CONTROLLER(oldController, msg.sender);
    }

    function setPublicSwap(bool public_)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        _publicSwap = public_;
    }

    /**
    * @notice Enables publicswap and finalizes the pool's tokens, price feeds, initial shares, balances and weights
    */
    function finalize()
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        require(_tokens.length >= Const.MIN_BOUND_TOKENS, "18");

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
        require(_records[token].bound, "2");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    /**
    * @notice Add liquidity to a pool and credit msg.sender
    * @dev The order of maxAmount of each token must be the same as the _tokens' addresses stored in the pool
    * @param poolAmountOut Amount of pool shares a LP wishes to receive
    * @param maxAmountsIn Maximum accepted token amount in
    */
    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
    external
    {
        _joinPool(msg.sender, poolAmountOut, maxAmountsIn);
    }

    /**
    * @notice Add liquidity to a pool and credit tx.origin
    * @dev The order of maxAmount of each token must be the same as the _tokens' addresses stored in the pool
    * This method is useful when joining a pool via a proxy contract
    * @param poolAmountOut Amount of pool shares a LP wishes to receive
    * @param maxAmountsIn Maximum accepted token amount in
    */
    function joinPoolForTxOrigin(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
    external
    {
        _joinPool(tx.origin, poolAmountOut, maxAmountsIn);
    }

    function _joinPool(address owner, uint256 poolAmountOut, uint256[] calldata maxAmountsIn) 
    internal     
    _logs_
    _lock_
    _whenNotPaused_{
        require(_finalized, "1");

        uint256 poolTotal = totalSupply();
        uint256 ratio = Num.bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "5");

        for (uint256 i; i < _tokens.length;) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountIn = Num.bmul(ratio, bal);
            require(tokenAmountIn != 0, "5");
            require(tokenAmountIn <= maxAmountsIn[i], "8");
            _records[t].balance = _records[t].balance + tokenAmountIn;
            emit LOG_JOIN(owner, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
            unchecked{++i;}
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(owner, poolAmountOut);
    }

    /**
    * @notice Remove liquidity from a pool
    * @dev The order of minAmount of each token must be the same as the _tokens' addresses stored in the pool
    * @param poolAmountIn Amount of pool shares a LP wishes to liquidate for tokens
    * @param minAmountsOut Minimum accepted token amount out
    */
    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
    external
    _logs_
    _lock_
    {
        require(_finalized, "1");

        uint256 poolTotal = totalSupply();
        uint256 exitFee = Num.bmul(poolAmountIn, Const.EXIT_FEE);
        uint256 pAiAfterExitFee = poolAmountIn - exitFee;
        uint256 ratio = Num.bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "5");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i; i < _tokens.length;) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = Num.bmul(ratio, bal);
            require(tokenAmountOut != 0, "5");
            require(tokenAmountOut >= minAmountsOut[i], "9");
            _records[t].balance = _records[t].balance - tokenAmountOut;
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
            unchecked{++i;}
        }

    }

    function joinswapExternAmountInMMM(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external
        _logs_
        _lock_
        _whenNotPaused_
        returns (uint poolAmountOut)

    {        
        require(_finalized, "1");
        require(_records[tokenIn].bound, "2");

        Struct.TokenGlobal memory tokenInInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;
        (tokenInInfo, remainingTokensInfo) = _getAllTokensInfo(tokenIn);

        {
            Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
                tokenAmountIn,
                _swapFee,
                Const.FALLBACK_SPREAD
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                priceStatisticsLookbackInRound,
                priceStatisticsLookbackInSec,
                block.timestamp
            );

            poolAmountOut = Math.calcPoolOutGivenSingleInMMM(
                _totalSupply,
                tokenInInfo,
                remainingTokensInfo,
                swapParameters,
                gbmParameters,
                hpParameters
            );
        }

        require(poolAmountOut >= minPoolAmountOut, "9");

        tokenInInfo.info.balance += tokenAmountIn;
        _checkJoinSwapPrices(tokenInInfo, remainingTokensInfo);
        _records[tokenIn].balance = tokenInInfo.info.balance;

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return poolAmountOut;
    }

    function joinswapPoolAmountOutMMM(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external
        _logs_
        _lock_
        _whenNotPaused_
        returns (uint tokenAmountIn)
    {
        require(_finalized, "1");
        require(_records[tokenIn].bound, "2");

        Struct.TokenGlobal memory tokenInInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;

        (tokenInInfo, remainingTokensInfo) = _getAllTokensInfo(tokenIn);

        {
            Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
                poolAmountOut,
                _swapFee,
                Const.FALLBACK_SPREAD
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                priceStatisticsLookbackInRound,
                priceStatisticsLookbackInSec,
                block.timestamp
            );
            tokenAmountIn = Math.calcSingleInGivenPoolOutMMM(
                _totalSupply,
                tokenInInfo,
                remainingTokensInfo,
                swapParameters,
                gbmParameters,
                hpParameters
            );
        }

        require(tokenAmountIn != 0, "5");
        require(tokenAmountIn <= maxAmountIn, "8");

        tokenInInfo.info.balance += tokenAmountIn;
        _checkJoinSwapPrices(tokenInInfo, remainingTokensInfo);
        _records[tokenIn].balance = tokenInInfo.info.balance;

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return tokenAmountIn;
    }

    function exitswapPoolAmountInMMM(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external
        _logs_
        _lock_
        _whenNotPaused_
        returns (uint tokenAmountOut)
    {
        require(_finalized, "1");
        require(_records[tokenOut].bound, "2");

        Struct.TokenGlobal memory tokenOutInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;
    
        (tokenOutInfo, remainingTokensInfo) = _getAllTokensInfo(tokenOut);

        {
            Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
                poolAmountIn,
                _swapFee,
                Const.FALLBACK_SPREAD
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                priceStatisticsLookbackInRound,
                priceStatisticsLookbackInSec,
                block.timestamp
            );

            tokenAmountOut = Math.calcSingleOutGivenPoolInMMM(
                _totalSupply,
                tokenOutInfo,
                remainingTokensInfo,
                swapParameters,
                gbmParameters,
                hpParameters
            );
        }

        require(tokenAmountOut >= minAmountOut, "9");
        
        tokenOutInfo.info.balance -= tokenAmountOut;
        _checkExitSwapPrices(tokenOutInfo, remainingTokensInfo);
        _records[tokenOut].balance = tokenOutInfo.info.balance;

        uint exitFee =  Num.bmul(poolAmountIn, Const.EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn - exitFee);
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return tokenAmountOut;
    }

    function exitswapExternAmountOutMMM(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external
        _logs_
        _lock_
        _whenNotPaused_
        returns (uint poolAmountIn)
    {
        require(_finalized, "1");
        require(_records[tokenOut].bound, "2");

        Struct.TokenGlobal memory tokenOutInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;

        (tokenOutInfo, remainingTokensInfo) = _getAllTokensInfo(tokenOut);

        {
            Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
                tokenAmountOut,
                _swapFee,
                Const.FALLBACK_SPREAD
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                priceStatisticsLookbackInRound,
                priceStatisticsLookbackInSec,
                block.timestamp
            );

            poolAmountIn = Math.calcPoolInGivenSingleOutMMM(
                _totalSupply,
                tokenOutInfo,
                remainingTokensInfo,
                swapParameters,
                gbmParameters,
                hpParameters
            );
        }

        require(poolAmountIn != 0, "5");
        require(poolAmountIn <= maxPoolAmountIn, "8");

        tokenOutInfo.info.balance -= tokenAmountOut;
        _checkExitSwapPrices(tokenOutInfo, remainingTokensInfo);
        _records[tokenOut].balance = tokenOutInfo.info.balance;

        uint exitFee = Num.bmul(poolAmountIn, Const.EXIT_FEE);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn - exitFee);
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return poolAmountIn;
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint256 amount)
    internal
    {
        IERC20(erc20).safeTransferFrom(from, address(this), amount);
    }

    function _pushUnderlying(address erc20, address to, uint256 amount)
    internal
    {
        IERC20(erc20).safeTransfer(to, amount);
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
        address oracle;
        uint256 initialPrice;
    }

    event LOG_PRICE(
        address indexed token,
        address oracle,
        uint256 value
    ) anonymous;

    function setDynamicCoverageFeesZ(uint64 _dynamicCoverageFeesZ)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        dynamicCoverageFeesZ = _dynamicCoverageFeesZ;
    }

    function setDynamicCoverageFeesHorizon(uint256 _dynamicCoverageFeesHorizon)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        require(_dynamicCoverageFeesHorizon >= Const.MIN_HORIZON, "22");
        dynamicCoverageFeesHorizon = _dynamicCoverageFeesHorizon;
    }

    function setPriceStatisticsLookbackInRound(uint8 _priceStatisticsLookbackInRound)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        require(_priceStatisticsLookbackInRound >= Const.MIN_LOOKBACK_IN_ROUND, "24");
        require(_priceStatisticsLookbackInRound <= Const.MAX_LOOKBACK_IN_ROUND, "25");
        priceStatisticsLookbackInRound = _priceStatisticsLookbackInRound;
    }

    function setPriceStatisticsLookbackInSec(uint256 _priceStatisticsLookbackInSec)
    external
    _logs_
    _lock_
    {
        require(!_finalized, "4");
        require(msg.sender == _controller, "3");
        require(_priceStatisticsLookbackInSec >= Const.MIN_LOOKBACK_IN_SEC, "26");
        priceStatisticsLookbackInSec = _priceStatisticsLookbackInSec;
    }

    function getCoverageParameters()
    external view
    returns (uint64, uint256, uint8, uint256)
    {
        return (
            dynamicCoverageFeesZ,
            dynamicCoverageFeesHorizon,
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec
        );
    }

    function getTokenOracleInitialPrice(address token)
    external view
    returns (uint256)
    {
        require(_records[token].bound, "2");
        return _prices[token].initialPrice;
    }

    function getTokenPriceOracle(address token)
    external view
    returns (address)
    {
        require(_records[token].bound, "2");
        return _prices[token].oracle;
    }

    /**
    * @notice Add a new token to the pool
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param _priceFeedAddress The token's Chainlink price feed
    */
    function bindMMM(address token, uint256 balance, uint80 denorm, address _priceFeedAddress)
    external
    {
        require(!_records[token].bound, "28");

        require(_tokens.length < Const.MAX_BOUND_TOKENS, "29");

        _records[token] = Record(
            {
                bound: true,
                index: uint8(_tokens.length),
                denorm: 0,    // balance and denorm will be validated
                balance: 0   // and set by `rebind`
            }
        );
        _tokens.push(token);
        _rebindMMM(token, balance, denorm, _priceFeedAddress);
    }

    /**
    * @notice Replace a binded token's balance, weight and price feed's address
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param _priceFeedAddress The token's Chainlink price feed
    */
    function rebindMMM(address token, uint256 balance, uint80 denorm, address _priceFeedAddress)
    external
    {
        require(_records[token].bound, "2");

        _rebindMMM(token, balance, denorm, _priceFeedAddress);
    }

    function _rebindMMM(address token, uint256 balance, uint80 denorm, address _priceFeedAddress)
    internal 
    _logs_
    _lock_
    _whenNotPaused_
    {
        require(msg.sender == _controller, "3");
        require(!_finalized, "4");

        require(denorm >= Const.MIN_WEIGHT, "30");
        require(denorm <= Const.MAX_WEIGHT, "31");
        require(balance >= Const.MIN_BALANCE, "32");

        // Adjust the denorm and totalWeight
        uint80 oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = _totalWeight + (denorm - oldWeight);
            require(_totalWeight <= Const.MAX_TOTAL_WEIGHT, "33");
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
                oracle: _priceFeedAddress,
                initialPrice: 0 // set right below
            }
        );
        _prices[token].initialPrice = ChainlinkUtils.getTokenLatestPrice(_prices[token].oracle);
        emit LOG_PRICE(token, _prices[token].oracle, _prices[token].initialPrice);
    }


    /**
    * @notice Remove a new token from the pool
    * @param token The token's address
    */
    function unbindMMM(address token)
    external
    _logs_
    _lock_
    {

        require(msg.sender == _controller, "3");
        require(_records[token].bound, "2");
        require(!_finalized, "4");

        uint256 tokenBalance = _records[token].balance;
        uint256 tokenExitFee = Num.bmul(tokenBalance, Const.EXIT_FEE);

        _totalWeight = _totalWeight - _records[token].denorm;

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint8 index = _records[token].index;
        uint256 last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        delete _records[token];
        delete _prices[token];

        _pushUnderlying(token, msg.sender, tokenBalance - tokenExitFee);
        _pushUnderlying(token, _factory, tokenExitFee);

    }

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
    external view
    _viewlock_
    returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound && _records[tokenOut].bound, "2");
        return Math.calcSpotPrice(
            _records[tokenIn].balance,
            _records[tokenIn].denorm,
            _records[tokenOut].balance,
            _records[tokenOut].denorm,
            0
        );
    }

    function swapExactAmountInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    external
    _logs_
    _lock_
    _whenNotPaused_
    returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        Struct.SwapResult memory swapResult;
        (swapResult, spotPriceAfter) = _getAmountOutGivenInMMM(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            maxPrice
        );

        _records[tokenIn].balance += tokenAmountIn;
        _records[tokenOut].balance -= swapResult.amount;

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, swapResult.amount, swapResult.spread);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, swapResult.amount);

        return (tokenAmountOut = swapResult.amount, spotPriceAfter);
    }

    function getAmountOutGivenInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    external view
    _viewlock_
    returns (Struct.SwapResult memory swapResult, uint256 spotPriceAfter)
    {
        return _getAmountOutGivenInMMM(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            maxPrice
        );
    }

    function _getAmountOutGivenInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    internal view
    returns (Struct.SwapResult memory swapResult, uint256 spotPriceAfter)
    {

        require(_records[tokenIn].bound && _records[tokenOut].bound, "2");
        require(_publicSwap, "10");

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        uint256 spotPriceBefore = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        require(spotPriceBefore <= maxPrice, "11");

        swapResult = _getAmountOutGivenInMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountIn,
            block.timestamp
        );
        require(swapResult.amount >= minAmountOut, "9");

        spotPriceAfter = Math.calcSpotPrice(
            tokenGlobalIn.info.balance + tokenAmountIn,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - swapResult.amount,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        require(spotPriceAfter >= spotPriceBefore, "5");
        require(spotPriceBefore <= Num.bdiv(tokenAmountIn, swapResult.amount), "5");
        require(
            Num.bdiv(
                Num.bmul(spotPriceAfter, Const.BONE - _swapFee),
                ChainlinkUtils.getTokenRelativePrice(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound)
            ) <= Const.MAX_PRICE_UNPEG_RATIO,
            "44"
        );

        return (swapResult, spotPriceAfter);
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

        Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
            tokenAmountIn,
            _swapFee,
            Const.FALLBACK_SPREAD
        );
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec,
            timestamp
        );

        return Math.calcOutGivenInMMM(
            tokenGlobalIn,
            tokenGlobalOut,
            ChainlinkUtils.getTokenRelativePrice(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound),
            swapParameters,
            gbmParameters,
            hpParameters
        );

    }

    function swapExactAmountOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    external
    _logs_
    _lock_
    _whenNotPaused_
    returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
    {

        Struct.SwapResult memory swapResult;
        (swapResult, spotPriceAfter)= _getAmountInGivenOutMMM(
            tokenIn,
            maxAmountIn,
            tokenOut,
            tokenAmountOut,
            maxPrice
        );

        _records[tokenIn].balance += swapResult.amount;
        _records[tokenOut].balance -= tokenAmountOut;

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, swapResult.amount, tokenAmountOut, swapResult.spread);

        _pullUnderlying(tokenIn, msg.sender, swapResult.amount);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountIn = swapResult.amount, spotPriceAfter);
    }

    function getAmountInGivenOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    external view
    _viewlock_
    returns (Struct.SwapResult memory swapResult, uint256 spotPriceAfter)
    {
        return _getAmountInGivenOutMMM(
            tokenIn,
            maxAmountIn,
            tokenOut,
            tokenAmountOut,
            maxPrice
        );
    }

    function _getAmountInGivenOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    internal view
    returns (Struct.SwapResult memory swapResult, uint256 spotPriceAfter)
    {

        require(_records[tokenIn].bound && _records[tokenOut].bound, "2");
        require(_publicSwap, "10");

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        uint256 spotPriceBefore = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        require(spotPriceBefore <= maxPrice, "11");

        swapResult = _getAmountInGivenOutMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountOut,
            block.timestamp
        );

        require(swapResult.amount <= maxAmountIn, "8");

        spotPriceAfter = Math.calcSpotPrice(
            tokenGlobalIn.info.balance + swapResult.amount,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - tokenAmountOut,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        require(spotPriceAfter >= spotPriceBefore, "5");
        require(spotPriceBefore <= Num.bdiv(swapResult.amount, tokenAmountOut), "5");
        require(
            Num.bdiv(
                Num.bmul(spotPriceAfter, Const.BONE - _swapFee),
                ChainlinkUtils.getTokenRelativePrice(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound)
            ) <= Const.MAX_PRICE_UNPEG_RATIO,
            "44"
        );

        return (swapResult, spotPriceAfter);
    }

    function _getAmountInGivenOutMMMWithTimestamp(
        Struct.TokenGlobal memory tokenGlobalIn,
        Struct.TokenGlobal memory tokenGlobalOut,
        uint256 tokenAmountOut,
        uint256 timestamp
    )
    internal view
    returns (Struct.SwapResult memory)
    {
        
        Struct.SwapParameters memory swapParameters = Struct.SwapParameters(
            tokenAmountOut,
            _swapFee,
            Const.FALLBACK_SPREAD
        );
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(dynamicCoverageFeesZ, dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            priceStatisticsLookbackInRound,
            priceStatisticsLookbackInSec,
            timestamp
        );

        return Math.calcInGivenOutMMM(
            tokenGlobalIn,
            tokenGlobalOut,
            ChainlinkUtils.getTokenRelativePrice(tokenGlobalIn.latestRound, tokenGlobalOut.latestRound),
            swapParameters,
            gbmParameters,
            hpParameters
        );

    }

    /**
    * @notice Compute the token historical performance since pool's inception
    * @param initialPrice The token's initial price
    * @param latestPrice The token's latest price
    * @return tokenGlobal The token historical performance since pool's inception
    */
    function _getTokenPerformance(uint256 initialPrice, uint256 latestPrice)
    internal pure returns (uint256) {
        return Num.bdiv(
            latestPrice,
            initialPrice
        );
    }

    /**
    * @notice Retrieves the given token's latest oracle data.
    * @dev We get:
    * - latest round Id
    * - latest price
    * - latest round timestamp
    * - token historical performance since pool's inception
    * @param token The token's address
    * @return tokenGlobal The latest tokenIn oracle data
    */
    function getTokenLatestInfo(address token)
    internal view returns (Struct.TokenGlobal memory tokenGlobal) {
        Record memory record = _records[token];
        Price memory price = _prices[token];
        Struct.LatestRound memory latestRound = ChainlinkUtils.getLatestRound(price.oracle);
        Struct.TokenRecord memory info = Struct.TokenRecord(
            record.balance,
            // we adjust the token's target weight (in value) based on its appreciation since the inception of the pool.
            Num.bmul(
                record.denorm,
                _getTokenPerformance(
                    price.initialPrice,
                    uint256(latestRound.price) // we consider the token price to be > 0
                )
            )
        );
        return (
            tokenGlobal = Struct.TokenGlobal(
                info,
                latestRound
            )
        );
    }

    /**
    * @notice Returns all the binded token's global information (token record + latest round info)  
    * @param swappedToken the address of the swapped token 
    * @return swappedTokenInfo swapped token's global information
    * @return remainingTokensInfo remaining tokens' global information
    */
    function _getAllTokensInfo(address swappedToken)
    private view returns (
        Struct.TokenGlobal memory swappedTokenInfo,
        Struct.TokenGlobal[] memory remainingTokensInfo
    ) {

        swappedTokenInfo = getTokenLatestInfo(swappedToken);

        uint nRemainingTokens = _tokens.length - 1;
        remainingTokensInfo = new Struct.TokenGlobal[](nRemainingTokens);
        
        // Extracting the remaining un-traded tokens' info
        uint count;
        for (uint i; count < nRemainingTokens;) {
            if (_tokens[i] != swappedToken) {
                remainingTokensInfo[count] = getTokenLatestInfo(_tokens[i]);
                unchecked{++count;}
            }
            unchecked{++i;}
        }

    }

    /**
    * @notice Check if the spot prices falls within the limits of the oracle price
    * - spot prices of the remaining tokens must be < oraclePrice * (Const.MAX_PRICE_UNPEG_RATIO)
    * @dev tokenInInfo.info.balance should contain the balance after the trade
    * - spot prices of the remaining tokens are computed in terms of tokenIn
    * @param tokenInInfo swapped token's info
    * @param remainingTokensInfo untraded tokens' info
    */
    function _checkJoinSwapPrices (
        Struct.TokenGlobal memory tokenInInfo,
        Struct.TokenGlobal[] memory remainingTokensInfo
    ) internal view {
        
        uint256 spotPriceAfter;

        for (uint256 i; i < remainingTokensInfo.length;)
        {
            spotPriceAfter = Math.calcSpotPrice(
                tokenInInfo.info.balance,
                tokenInInfo.info.weight,
                remainingTokensInfo[i].info.balance,
                remainingTokensInfo[i].info.weight,
                0
            );

            require(
                Num.bdiv(
                    spotPriceAfter,
                    ChainlinkUtils.getTokenRelativePrice(tokenInInfo.latestRound, remainingTokensInfo[i].latestRound)
                ) <= Const.MAX_PRICE_UNPEG_RATIO,
                "44"
            );
            unchecked{++i;}
        }
    }

    /**
    * @notice Check if the spot prices falls within the limits of the oracle price
    * - spot price of tokenOut must be < oraclePrice * (Const.MAX_PRICE_UNPEG_RATIO)
    * @dev tokenOutInfo.info.balance should contain the balance after the trade
    * - spot price of tokenOut is computed in terms of the remaining tokens independently
    * @param tokenOutInfo swapped token's info
    * @param remainingTokensInfo untraded tokens' info
    */
    function _checkExitSwapPrices (
        Struct.TokenGlobal memory tokenOutInfo,
        Struct.TokenGlobal[] memory remainingTokensInfo
    ) internal view {
        
        uint256 spotPriceAfter;

        for (uint256 i; i < remainingTokensInfo.length;)
        {
            spotPriceAfter = Math.calcSpotPrice(
                remainingTokensInfo[i].info.balance,
                remainingTokensInfo[i].info.weight,
                tokenOutInfo.info.balance,
                tokenOutInfo.info.weight,
                0
            );

            require(
                Num.bdiv(
                    spotPriceAfter,
                    ChainlinkUtils.getTokenRelativePrice(remainingTokensInfo[i].latestRound, tokenOutInfo.latestRound)
                ) <= Const.MAX_PRICE_UNPEG_RATIO,
                "44"
            );
            unchecked{++i;}
        }
    }

}