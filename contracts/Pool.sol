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

import "./interfaces/IDecimals.sol";

import "./ChainlinkUtils.sol";

import "./Errors.sol";

contract Pool is PoolToken {

    using SafeERC20 for IERC20; 

    struct Record {
        bool bound;   // is token bound to pool
        uint8 index;   // private
        uint8 decimals; // token decimals + oracle decimals
        uint80 denorm;  // denormalized weight
        uint256 balance;
    }

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut,
        uint256         spread,
        uint256         taxBaseIn,
        uint256         priceIn,
        uint256         priceOut
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

    event LOG_NEW_ORACLE_STATE(
        address indexed token,
        address oracle,
        uint256 price,
        uint8   decimals,
        string  description
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
        _require(!_mutex, Err.REENTRY);
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
        _require(!_mutex, Err.REENTRY);
        _;
    }

    function _whenNotPaused() private view {
        IPausedFactory(_factory).whenNotPaused();
    }

    modifier _whenNotPaused_() {
        _whenNotPaused();
        _;
    }

    function _onlyAdmins() private view {
        if (msg.sender == _controller) {
            _require(!_finalized, Err.IS_FINALIZED);
        }
        else if (msg.sender == _factory) {
            _require(!_revokedFactoryControl, Err.FACTORY_CONTROL_REVOKED);
        }
        else {
            _revert(Err.NOT_ADMIN);
        }
    }

    modifier _onlyAdmins_() {
        _onlyAdmins();
        _;
    }

    // prevents token transfers with fees
    modifier _checkBalanceAfterTransfer_(address erc20, uint amount) {
        uint expectedBalance = IERC20(erc20).balanceOf(address(this)) + amount;
        _;
        uint currentBalance = IERC20(erc20).balanceOf(address(this));
        _require(expectedBalance == currentBalance, Err.UNEXPECTED_BALANCE);
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
    bool private _revokedFactoryControl; // if true factory cannot change pool parameters
    address immutable private _factory; // Factory address to push token exitFee to

    uint64 private _dynamicCoverageFeesZ;
    uint256 private _dynamicCoverageFeesHorizon;
    uint8 private _priceStatisticsLookbackInRound;
    uint256 private _priceStatisticsLookbackInSec;
    uint8 private _priceStatisticsLookbackStepInRound;
    uint256 private _maxPriceUnpegRatio;

    // `setSwapFee` and `finalize` _require CONTROL
    uint256 private _swapFee;
        
    mapping(address=>Struct.OracleState) private _oraclesInitialState;


    constructor() {
        _controller = msg.sender;
        _factory = msg.sender;
        _swapFee = Const.MIN_FEE;
        _priceStatisticsLookbackInRound = Const.BASE_LOOKBACK_IN_ROUND;
        _priceStatisticsLookbackInSec = Const.BASE_LOOKBACK_IN_SEC;
        _dynamicCoverageFeesZ = Const.BASE_Z;
        _dynamicCoverageFeesHorizon = Const.BASE_HORIZON;
        _priceStatisticsLookbackStepInRound = Const.LOOKBACK_STEP_IN_ROUND;
        _maxPriceUnpegRatio = Const.BASE_MAX_PRICE_UNPEG_RATIO;
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
        _require(_records[token].bound, Err.NOT_BOUND);
        return _records[token].denorm;
    }

    function getBalance(address token)
    external view
    returns (uint256)
    {
        _require(_records[token].bound, Err.NOT_BOUND);
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
    _onlyAdmins_
    {
        _require(swapFee >= Const.MIN_FEE, Err.MIN_FEE);
        _require(swapFee <= Const.MAX_FEE, Err.MAX_FEE);
        _swapFee = swapFee;
    }

    /**
    * @notice Allows a controller to transfer ownership to a new address
    * @dev It is recommended to use transferOwnership/acceptOwnership logic for safer transfers
    * to avoid any faulty input
    * This function is useful when creating pools using a proxy contract and transfer pool assets
    * WARNING: Binded assets are also transferred to the new controller if the pool is not finalized
    */  
    function setControllerAndTransfer(address manager)
    external
    _lock_
    {
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        _require(manager != address(0), Err.NULL_CONTROLLER);
        _controller = manager;
        _pendingController = address(0);
        emit LOG_NEW_CONTROLLER(msg.sender, manager);
    }
    
    /**
    * @notice Allows a controller to begin transferring ownership to a new address
    * @dev The function will revert if there are binded tokens in an un-finalized pool
    * This prevents any accidental loss of funds for the current controller
    */
    function transferOwnership(address _to)
    external
    _logs_
    {
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        if(!_finalized){
            // This condition prevents any accidental transfer of funds between the old and new controller
            // when the pool is not finalized
            _require(_tokens.length == 0 ,Err.BINDED_TOKENS);
        }
        _pendingController = _to;
    }

    /**
    * @notice Allows a controller transfer to be completed by the recipient
    */
    function acceptOwnership()
    external
    {
        _require(msg.sender == _pendingController, Err.NOT_PENDING_CONTROLLER);

        address oldController = _controller;
        _controller = msg.sender;
        _pendingController = address(0);

        emit LOG_NEW_CONTROLLER(oldController, msg.sender);
    }

    /**
    * @notice Revokes factory control over pool parameters
    */
    function revokeFactoryControl()
    external
    _logs_
    {
        _require(msg.sender == _factory, Err.NOT_FACTORY);
        _revokedFactoryControl = true;
    }

    /**
    * @notice Gives back factory control over pool parameters
    */
    function giveFactoryControl()
    external
    _logs_
    {
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        _revokedFactoryControl = false;
    }

    /**
    * @notice Enables public swaps on the pool but does not finalize the parameters
    * @dev Unfinalized pool enables exclusively the controller to add liquidity into the pool
    */
    function setPublicSwap(bool public_)
    external
    _logs_
    _lock_
    {
        _require(!_finalized, Err.IS_FINALIZED);
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
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
        _require(!_finalized, Err.IS_FINALIZED);
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        _require(_tokens.length >= Const.MIN_BOUND_TOKENS, Err.MIN_TOKENS);

        _finalized = true;
        _publicSwap = true;

        _mintPoolShare(Const.INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, Const.INIT_POOL_SUPPLY);
    }

    /**
    * @notice Absorb any tokens that have been sent to this contract into the pool
    * @param token The token's address
    */
    function gulp(address token)
    external
    _logs_
    _lock_
    {
        _require(_records[token].bound, Err.NOT_BOUND);
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    /**
    * @notice Get the token amounts in required and pool shares received when joining
    * the pool given an amount of tokenIn
    * @dev The amountIn of the specified token as input may differ at the exit due to
    * rounding discrepancies
    * @param  tokenIn The address of tokenIn
    * @param  tokenAmountIn The approximate amount of tokenIn to be swapped
    * @return poolAmountOut The pool amount out received
    * @return tokenAmountsIn The exact amounts of tokenIn needed
    */
    function getJoinPool(address tokenIn, uint256 tokenAmountIn)
    external
    view
    _viewlock_
    returns (uint256 poolAmountOut, uint256[] memory tokenAmountsIn)
    {
        _require(_finalized, Err.NOT_FINALIZED);
        _require(_records[tokenIn].bound, Err.NOT_BOUND);

        uint256 ratio = Num.bdivTruncated(tokenAmountIn, _records[tokenIn].balance);
        
        uint256 poolTotal = _totalSupply;
        poolAmountOut = Num.bmul(ratio, poolTotal);
        // ratio is re-evaluated to avoid any calculation discrepancies with joinPool
        ratio = Num.bdiv(poolAmountOut, poolTotal);

        uint256 tokensLength = _tokens.length;
        tokenAmountsIn = new uint256[](tokensLength);

        for (uint256 i; i < tokensLength;) {
            address t     = _tokens[i];
            uint256 bal   = _records[t].balance;
            tokenAmountIn = Num.bmul(ratio, bal);
            _require(tokenAmountIn != 0, Err.MATH_APPROX);
            tokenAmountsIn[i] = tokenAmountIn;
            unchecked{++i;}
        }
        
        return (poolAmountOut, tokenAmountsIn);

    }


    /**
    * @notice Add liquidity to a pool and credit msg.sender
    * @dev The order of maxAmount of each token must be the same as the _tokens' addresses stored in the pool
    * @param poolAmountOut Amount of pool shares a LP wishes to receive
    * @param maxAmountsIn Maximum accepted token amount in
    */
    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
    _logs_
    _lock_
    _whenNotPaused_
    external
    {
        _require(_finalized, Err.NOT_FINALIZED);
        _require(maxAmountsIn.length == _tokens.length, Err.INPUT_LENGTH_MISMATCH);

        uint256 ratio = Num.bdiv(poolAmountOut, _totalSupply);
        _require(ratio != 0, Err.MATH_APPROX);

        for (uint256 i; i < maxAmountsIn.length;) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountIn = Num.bmul(ratio, bal);
            _require(tokenAmountIn != 0, Err.MATH_APPROX);
            _require(tokenAmountIn <= maxAmountsIn[i], Err.LIMIT_IN);
            _records[t].balance = bal + tokenAmountIn;
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
            unchecked{++i;}
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    /**
    * @notice Get the token amounts received for a given pool shares in
    * @param poolAmountIn The amount of pool shares a LP wishes to liquidate for tokens
    * @return tokenAmountsOut The token amounts received
    */
    function getExitPool(uint256 poolAmountIn)
    external
    view
    _viewlock_
    returns (uint256[] memory tokenAmountsOut)
    {

        uint256 exitFee = Num.bmul(poolAmountIn, Const.EXIT_FEE);
        uint256 pAiAfterExitFee = poolAmountIn - exitFee;
        uint256 ratio = Num.bdivTruncated(pAiAfterExitFee, _totalSupply);

        uint256 tokensLength = _tokens.length;
        tokenAmountsOut = new uint256[](tokensLength);

        for (uint256 i; i < tokensLength;) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = Num.bmulTruncated(ratio, bal);
            _require(tokenAmountOut != 0, Err.MATH_APPROX);
            tokenAmountsOut[i] = tokenAmountOut;
            unchecked{++i;}
        }

        return tokenAmountsOut;
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
        _require(_finalized, Err.NOT_FINALIZED);
        _require(minAmountsOut.length == _tokens.length, Err.INPUT_LENGTH_MISMATCH);

        uint256 exitFee = Num.bmul(poolAmountIn, Const.EXIT_FEE);
        uint256 pAiAfterExitFee = poolAmountIn - exitFee;
        uint256 ratio = Num.bdivTruncated(pAiAfterExitFee, _totalSupply);
        _require(ratio != 0, Err.MATH_APPROX);

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i; i < minAmountsOut.length;) {
            address t = _tokens[i];
            uint256 bal = _records[t].balance;
            uint256 tokenAmountOut = Num.bmulTruncated(ratio, bal);
            _require(tokenAmountOut != 0, Err.MATH_APPROX);
            _require(tokenAmountOut >= minAmountsOut[i], Err.LIMIT_OUT);

            _records[t].balance = _records[t].balance - tokenAmountOut;
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
            unchecked{++i;}
        }

    }

    /**
    * @notice Computes the amount of pool tokens received when joining a pool with a single asset of fixed amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the joinswap
    * @param tokenIn The address of tokenIn
    * @param tokenAmountIn The amount of tokenIn to be added to the pool
    * @return poolAmountOut The received pool token amount out
    */
    function getJoinswapExternAmountInMMM(address tokenIn, uint256 tokenAmountIn)
    external
    view
    _viewlock_
    returns (uint256 poolAmountOut)
    {
        return (poolAmountOut = _getJoinswapExternAmountInMMM(tokenIn, tokenAmountIn));
    }

    function _getJoinswapExternAmountInMMM(address tokenIn, uint256 tokenAmountIn)
    internal
    view
    returns (uint256 poolAmountOut)
    {
        _require(_finalized, Err.NOT_FINALIZED);
        _require(_records[tokenIn].bound, Err.NOT_BOUND);
        _require(tokenAmountIn <= Num.bmul(_records[tokenIn].balance, Const.MAX_IN_RATIO), Err.MAX_IN_RATIO);

        Struct.TokenGlobal memory tokenInInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;
        (tokenInInfo, remainingTokensInfo) = _getAllTokensInfo(tokenIn);

        {
            Struct.JoinExitSwapParameters memory joinswapParameters = Struct.JoinExitSwapParameters(
                tokenAmountIn,
                _swapFee,
                Const.FALLBACK_SPREAD,
                _totalSupply
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(_dynamicCoverageFeesZ, _dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                _priceStatisticsLookbackInRound,
                _priceStatisticsLookbackInSec,
                block.timestamp,
                _priceStatisticsLookbackStepInRound
            );

            poolAmountOut = Math.calcPoolOutGivenSingleInMMM(
                tokenInInfo,
                remainingTokensInfo,
                joinswapParameters,
                gbmParameters,
                hpParameters
            );

            tokenInInfo.info.balance += tokenAmountIn;
            _checkJoinSwapPrices(tokenInInfo, remainingTokensInfo);

            return poolAmountOut;
        }
    }

    /**
    * @notice Join a pool with a single asset with a fixed amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the joinswap
    * @param tokenIn The address of tokenIn
    * @param tokenAmountIn The amount of tokenIn to be added to the pool
    * @param minPoolAmountOut The minimum amount of pool tokens that can be received
    * @return poolAmountOut The received pool amount out
    */
    function joinswapExternAmountInMMM(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
    external
    _logs_
    _lock_
    _whenNotPaused_
    returns (uint poolAmountOut)
    {        
        poolAmountOut = _getJoinswapExternAmountInMMM(
            tokenIn, tokenAmountIn
        );

        _require(poolAmountOut >= minPoolAmountOut, Err.LIMIT_OUT);

        _records[tokenIn].balance = _records[tokenIn].balance + tokenAmountIn;

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return poolAmountOut;
    }

    /**
    * @notice Exit a pool with a single asset given the pool token amount in
    * @dev The remaining tokens designate the tokens whose balances do not change during the exitswap
    * @param tokenOut The address of tokenOut
    * @param poolAmountIn The fixed amount of pool tokens in
    * @param minAmountOut The minimum amount of token out that can be receied
    * @return tokenAmountOut The received token amount out
    */
    function exitswapPoolAmountInMMM(address tokenOut, uint poolAmountIn, uint minAmountOut)
    external
    _logs_
    _lock_
    _whenNotPaused_
    returns (uint tokenAmountOut)
    {
        _require(_finalized, Err.NOT_FINALIZED);
        _require(_records[tokenOut].bound, Err.NOT_BOUND);

        Struct.TokenGlobal memory tokenOutInfo;
        Struct.TokenGlobal[] memory remainingTokensInfo;

        (tokenOutInfo, remainingTokensInfo) = _getAllTokensInfo(tokenOut);

        {
            Struct.JoinExitSwapParameters memory exitswapParameters = Struct.JoinExitSwapParameters(
                poolAmountIn,
                _swapFee,
                Const.FALLBACK_SPREAD,
                _totalSupply
            );
            Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(_dynamicCoverageFeesZ, _dynamicCoverageFeesHorizon);
            Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
                _priceStatisticsLookbackInRound,
                _priceStatisticsLookbackInSec,
                block.timestamp,
                _priceStatisticsLookbackStepInRound
            );

            tokenAmountOut = Math.calcSingleOutGivenPoolInMMM(
                tokenOutInfo,
                remainingTokensInfo,
                exitswapParameters,
                gbmParameters,
                hpParameters
            );
            _require(tokenAmountOut <= Num.bmul(_records[tokenOut].balance, Const.MAX_OUT_RATIO), Err.MAX_OUT_RATIO);
        }

        _require(tokenAmountOut >= minAmountOut, Err.LIMIT_OUT);

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

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint256 amount)
    internal
    _checkBalanceAfterTransfer_(erc20, amount)
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

    function setDynamicCoverageFeesZ(uint64 dynamicCoverageFeesZ)
    external
    _logs_
    _lock_
    _onlyAdmins_
    {
        _dynamicCoverageFeesZ = dynamicCoverageFeesZ;
    }

    function setDynamicCoverageFeesHorizon(uint256 dynamicCoverageFeesHorizon)
    external
    _logs_
    _lock_
    _onlyAdmins_
    {
        _require(dynamicCoverageFeesHorizon >= Const.MIN_HORIZON, Err.MIN_HORIZON);
        _dynamicCoverageFeesHorizon = dynamicCoverageFeesHorizon;
    }

    function setPriceStatisticsLookbackInRound(uint8 priceStatisticsLookbackInRound)
    external
    _logs_
    _lock_
    _onlyAdmins_
    {
        _require(priceStatisticsLookbackInRound >= Const.MIN_LOOKBACK_IN_ROUND, Err.MIN_LB_PERIODS);
        _require(priceStatisticsLookbackInRound <= Const.MAX_LOOKBACK_IN_ROUND, Err.MAX_LB_PERIODS);
        _priceStatisticsLookbackInRound = priceStatisticsLookbackInRound;
    }

    function setPriceStatisticsLookbackInSec(uint256 priceStatisticsLookbackInSec)
    external
    _logs_
    _lock_
    _onlyAdmins_
    {
        _require(priceStatisticsLookbackInSec >= Const.MIN_LOOKBACK_IN_SEC, Err.MIN_LB_SECS);
        _priceStatisticsLookbackInSec = priceStatisticsLookbackInSec;
    }

    function setPriceStatisticsLookbackStepInRound(uint8 priceStatisticsLookbackStepInRound)
    external
    _logs_
    _lock_
    _onlyAdmins_
    {
        _require(priceStatisticsLookbackStepInRound >= Const.MIN_LOOKBACK_STEP_IN_ROUND, Err.MIN_LB_STEP_PERIODS);
        _priceStatisticsLookbackStepInRound = priceStatisticsLookbackStepInRound;
    }

    function setMaxPriceUnpegRatio(uint256 maxPriceUnpegRatio)
    external
    _logs_
    _lock_
    {
        _require(msg.sender == _factory, Err.NOT_FACTORY);
        _require(!_revokedFactoryControl, Err.FACTORY_CONTROL_REVOKED);
        _require(maxPriceUnpegRatio >= Const.MIN_MAX_PRICE_UNPEG_RATIO, Err.MIN_MAX_PRICE_UNPEG_RATIO);
        _require(maxPriceUnpegRatio <= Const.MAX_MAX_PRICE_UNPEG_RATIO, Err.MAX_MAX_PRICE_UNPEG_RATIO);
        _maxPriceUnpegRatio = maxPriceUnpegRatio;
    }

    function getCoverageParameters()
    external view
    returns (uint64, uint256, uint8, uint256, uint8, uint256)
    {
        return (
            _dynamicCoverageFeesZ,
            _dynamicCoverageFeesHorizon,
            _priceStatisticsLookbackInRound,
            _priceStatisticsLookbackInSec,
            _priceStatisticsLookbackStepInRound,
            _maxPriceUnpegRatio
        );
    }

    function getTokenOracleInitialPrice(address token)
    external view
    returns (uint256)
    {
        _require(_records[token].bound, Err.NOT_BOUND);
        return _oraclesInitialState[token].price;
    }

    function getTokenPriceOracle(address token)
    external view
    returns (address)
    {
        _require(_records[token].bound, Err.NOT_BOUND);
        return _oraclesInitialState[token].oracle;
    }

    /**
    * @notice Add a new token to the pool
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param priceFeedAddress The token's Chainlink price feed
    */
    function bindMMM(address token, uint256 balance, uint80 denorm, address priceFeedAddress)
    external
    {
        _require(!_records[token].bound, Err.IS_BOUND);

        _require(_tokens.length < Const.MAX_BOUND_TOKENS, Err.MAX_TOKENS);

        _records[token] = Record(
            {
                bound: true,
                index: uint8(_tokens.length),
                decimals: 0,
                denorm: 0,    // balance and denorm will be validated
                balance: 0   // and set by `rebind`
            }
        );
        _tokens.push(token);
        _rebindMMM(token, balance, denorm, priceFeedAddress);
    }

    /**
    * @notice Replace a binded token's balance, weight and price feed's address
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param priceFeedAddress The token's Chainlink price feed
    */
    function rebindMMM(address token, uint256 balance, uint80 denorm, address priceFeedAddress)
    external
    {
        _require(_records[token].bound, Err.NOT_BOUND);

        _rebindMMM(token, balance, denorm, priceFeedAddress);
    }

    function _rebindMMM(address token, uint256 balance, uint80 denorm, address priceFeedAddress)
    internal 
    _logs_
    _lock_
    _whenNotPaused_
    {
        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        _require(!_finalized, Err.IS_FINALIZED);
        _require(_pendingController == address(0), Err.PENDING_NEW_CONTROLLER);

        _require(denorm >= Const.MIN_WEIGHT, Err.MIN_WEIGHT);
        _require(denorm <= Const.MAX_WEIGHT, Err.MAX_WEIGHT);
        _require(balance >= Const.MIN_BALANCE, Err.MIN_BALANCE);

        // Adjust the denorm and totalWeight
        uint80 oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = _totalWeight + (denorm - oldWeight);
            _require(_totalWeight <= Const.MAX_TOTAL_WEIGHT, Err.MAX_TOTAL_WEIGHT);
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

        (
            uint256 price,
            uint8 decimals,
            string memory description
        ) = ChainlinkUtils.getTokenLatestPrice(priceFeedAddress);

        _records[token].decimals = decimals + _tryGetTokenDecimals(token);

        // Updating oracle state
        _oraclesInitialState[token] = Struct.OracleState(
            {
                oracle: priceFeedAddress,
                price: price // set right below
            }
        );

        emit LOG_NEW_ORACLE_STATE(
            token,
            priceFeedAddress,
            price,
            decimals,
            description
        );
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

        _require(msg.sender == _controller, Err.NOT_CONTROLLER);
        _require(_records[token].bound, Err.NOT_BOUND);
        _require(!_finalized, Err.IS_FINALIZED);

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
        delete _oraclesInitialState[token];

        _pushUnderlying(token, msg.sender, tokenBalance - tokenExitFee);
        _pushUnderlying(token, _factory, tokenExitFee);

    }

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
    external view
    _viewlock_
    returns (uint256 spotPrice)
    {
        _require(_records[tokenIn].bound && _records[tokenOut].bound, Err.NOT_BOUND);
        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);
        return spotPrice = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            0
        );
    }

    /**
    * @notice Swap two tokens given the exact amount of token in
    * @param tokenIn The address of the input token
    * @param tokenAmountIn The exact amount of tokenIn to be swapped
    * @param tokenOut The address of the received token
    * @param minAmountOut The minimum accepted amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    */
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
        (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult) = _getAmountOutGivenInMMM(
            tokenIn,
            tokenAmountIn,
            tokenOut,
            minAmountOut,
            maxPrice
        );

        _records[tokenIn].balance += tokenAmountIn;
        _records[tokenOut].balance -= swapResult.amount;

        emit LOG_SWAP(
            msg.sender, tokenIn, tokenOut, tokenAmountIn,
            swapResult.amount, swapResult.spread, swapResult.taxBaseIn,
            priceResult.priceIn, priceResult.priceOut
        );

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, swapResult.amount);

        return (tokenAmountOut = swapResult.amount, spotPriceAfter = priceResult.spotPriceAfter);
    }

    /**
    * @notice Computes the amount of tokenOut received when swapping a fixed amount of tokenIn
    * @param tokenIn The address of the input token
    * @param tokenAmountIn The fixed amount of tokenIn to be swapped
    * @param tokenOut The address of the received token
    * @param minAmountOut The minimum amount of tokenOut that can be received
    * @param maxPrice The maximum spot price accepted before the swap
    */
    function getAmountOutGivenInMMM(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
    external view
    _viewlock_
    returns (Struct.SwapResult memory, Struct.PriceResult memory)
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
    returns (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult)
    {

        _require(_records[tokenIn].bound && _records[tokenOut].bound, Err.NOT_BOUND);
        _require(_publicSwap, Err.SWAP_NOT_PUBLIC);

        _require(tokenAmountIn <= Num.bmul(_records[tokenIn].balance, Const.MAX_IN_RATIO), Err.MAX_IN_RATIO);

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        priceResult.spotPriceBefore = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        _require(priceResult.spotPriceBefore <= maxPrice, Err.BAD_LIMIT_PRICE);

        swapResult = _getAmountOutGivenInMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountIn,
            block.timestamp
        );
        _require(swapResult.amount >= minAmountOut, Err.LIMIT_OUT);

        priceResult.spotPriceAfter = Math.calcSpotPrice(
            tokenGlobalIn.info.balance + tokenAmountIn,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - swapResult.amount,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        _require(priceResult.spotPriceAfter >= priceResult.spotPriceBefore, Err.MATH_APPROX);
        uint256 maxAmount = Num.bdivTruncated(tokenAmountIn, priceResult.spotPriceBefore);
        if (swapResult.amount > maxAmount) {
            swapResult.amount = maxAmount;
        }
        _require(
            Num.bdiv(
                Num.bmul(priceResult.spotPriceAfter, Const.BONE - _swapFee),
                ChainlinkUtils.getTokenRelativePrice(
                    tokenGlobalIn.latestRound.price,
                    tokenGlobalIn.info.decimals,
                    tokenGlobalOut.latestRound.price,
                    tokenGlobalOut.info.decimals
                )
            ) <= _maxPriceUnpegRatio,
            Err.MAX_PRICE_UNPEG_RATIO
        );

        priceResult.priceIn = tokenGlobalIn.latestRound.price;
        priceResult.priceOut = tokenGlobalOut.latestRound.price;

        return (swapResult, priceResult);
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
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(_dynamicCoverageFeesZ, _dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            _priceStatisticsLookbackInRound,
            _priceStatisticsLookbackInSec,
            timestamp,
            _priceStatisticsLookbackStepInRound
        );

        return Math.calcOutGivenInMMM(
            tokenGlobalIn,
            tokenGlobalOut,
            ChainlinkUtils.getTokenRelativePrice(
                tokenGlobalIn.latestRound.price,
                tokenGlobalIn.info.decimals,
                tokenGlobalOut.latestRound.price,
                tokenGlobalOut.info.decimals
            ),
            swapParameters,
            gbmParameters,
            hpParameters
        );

    }

    /**
    * @notice Swap two tokens given the exact amount of token out
    * @param tokenIn The address of the input token
    * @param maxAmountIn The maximum amount of tokenIn that can be swapped
    * @param tokenOut The address of the received token
    * @param tokenAmountOut The exact amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    */
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

        (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult) = _getAmountInGivenOutMMM(
            tokenIn,
            maxAmountIn,
            tokenOut,
            tokenAmountOut,
            maxPrice
        );

        _records[tokenIn].balance += swapResult.amount;
        _records[tokenOut].balance -= tokenAmountOut;

        emit LOG_SWAP(
            msg.sender, tokenIn, tokenOut, swapResult.amount,
            tokenAmountOut, swapResult.spread, swapResult.taxBaseIn,
            priceResult.priceIn, priceResult.priceOut
        );

        _pullUnderlying(tokenIn, msg.sender, swapResult.amount);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountIn = swapResult.amount, spotPriceAfter = priceResult.spotPriceAfter);
    }

    /**
    * @notice Computes the amount of tokenIn needed to receive a fixed amount of tokenOut
    * @param tokenIn The address of the input token
    * @param maxAmountIn The maximum amount of tokenIn that can be swapped
    * @param tokenOut The address of the received token
    * @param tokenAmountOut The fixed accepted amount of tokenOut to be received
    * @param maxPrice The maximum spot price accepted before the swap
    */
    function getAmountInGivenOutMMM(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
    external view
    _viewlock_
    returns (Struct.SwapResult memory, Struct.PriceResult memory)
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
    returns (Struct.SwapResult memory swapResult, Struct.PriceResult memory priceResult)
    {

        _require(_records[tokenIn].bound && _records[tokenOut].bound, Err.NOT_BOUND);
        _require(_publicSwap, Err.SWAP_NOT_PUBLIC);

        _require(tokenAmountOut <= Num.bmul(_records[tokenOut].balance, Const.MAX_OUT_RATIO), Err.MAX_OUT_RATIO);

        Struct.TokenGlobal memory tokenGlobalIn = getTokenLatestInfo(tokenIn);
        Struct.TokenGlobal memory tokenGlobalOut = getTokenLatestInfo(tokenOut);

        priceResult.spotPriceBefore = Math.calcSpotPrice(
            tokenGlobalIn.info.balance,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        _require(priceResult.spotPriceBefore <= maxPrice, Err.BAD_LIMIT_PRICE);

        swapResult = _getAmountInGivenOutMMMWithTimestamp(
            tokenGlobalIn,
            tokenGlobalOut,
            tokenAmountOut,
            block.timestamp
        );

        _require(swapResult.amount <= maxAmountIn, Err.LIMIT_IN);

        priceResult.spotPriceAfter = Math.calcSpotPrice(
            tokenGlobalIn.info.balance + swapResult.amount,
            tokenGlobalIn.info.weight,
            tokenGlobalOut.info.balance - tokenAmountOut,
            tokenGlobalOut.info.weight,
            _swapFee
        );

        _require(priceResult.spotPriceAfter >= priceResult.spotPriceBefore, Err.MATH_APPROX);
        uint256 minAmount = Num.bmul(priceResult.spotPriceBefore, tokenAmountOut) + 1;
        if (swapResult.amount < minAmount) {
            swapResult.amount = minAmount;
        }
        _require(
            Num.bdiv(
                Num.bmul(priceResult.spotPriceAfter, Const.BONE - _swapFee),
                ChainlinkUtils.getTokenRelativePrice(
                    tokenGlobalIn.latestRound.price,
                    tokenGlobalIn.info.decimals,
                    tokenGlobalOut.latestRound.price,
                    tokenGlobalOut.info.decimals
                )
            ) <= _maxPriceUnpegRatio,
            Err.MAX_PRICE_UNPEG_RATIO
        );

        priceResult.priceIn = tokenGlobalIn.latestRound.price;
        priceResult.priceOut = tokenGlobalOut.latestRound.price;

        return (swapResult, priceResult);
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
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(_dynamicCoverageFeesZ, _dynamicCoverageFeesHorizon);
        Struct.HistoricalPricesParameters memory hpParameters = Struct.HistoricalPricesParameters(
            _priceStatisticsLookbackInRound,
            _priceStatisticsLookbackInSec,
            timestamp,
            _priceStatisticsLookbackStepInRound
        );

        return Math.calcInGivenOutMMM(
            tokenGlobalIn,
            tokenGlobalOut,
            ChainlinkUtils.getTokenRelativePrice(
                        tokenGlobalIn.latestRound.price,
                        tokenGlobalIn.info.decimals,
                        tokenGlobalOut.latestRound.price,
                        tokenGlobalOut.info.decimals
            ),
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
        Struct.OracleState memory initialOracleState = _oraclesInitialState[token];
        Struct.LatestRound memory latestRound = ChainlinkUtils.getLatestRound(initialOracleState.oracle);
        Struct.TokenRecord memory info = Struct.TokenRecord(
            record.decimals,
            record.balance,
            // we adjust the token's target weight (in value) based on its appreciation since the inception of the pool.
            Num.bmul(
                record.denorm,
                _getTokenPerformance(
                    initialOracleState.price,
                    latestRound.price
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
    * - spot prices of the remaining tokens must be < oraclePrice * _maxPriceUnpegRatio
    * @dev tokenInInfo.info.balance should contain the balance after the trade
    * - spot prices of the remaining tokens are computed in terms of tokenIn
    * @param tokenInInfo swapped token's info
    * @param remainingTokensInfo remaining tokens' info
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

            _require(
                Num.bdiv(
                    spotPriceAfter,
                    ChainlinkUtils.getTokenRelativePrice(
                        tokenInInfo.latestRound.price,
                        tokenInInfo.info.decimals,
                        remainingTokensInfo[i].latestRound.price,
                        remainingTokensInfo[i].info.decimals
                    )
                ) <= _maxPriceUnpegRatio,
                Err.MAX_PRICE_UNPEG_RATIO
            );
            unchecked{++i;}
        }
    }

    /**
    * @notice Check if the spot prices falls within the limits of the oracle price
    * - spot price of tokenOut must be < oraclePrice * _maxPriceUnpegRatio
    * @dev tokenOutInfo.info.balance should contain the balance after the trade
    * - spot price of tokenOut is computed in terms of the remaining tokens independently
    * @param tokenOutInfo swapped token's info
    * @param remainingTokensInfo remaining tokens' info
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

            _require(
                Num.bdiv(
                    spotPriceAfter,
                    ChainlinkUtils.getTokenRelativePrice(
                        remainingTokensInfo[i].latestRound.price,
                        remainingTokensInfo[i].info.decimals,
                        tokenOutInfo.latestRound.price,
                        tokenOutInfo.info.decimals
                    )    
                ) <= _maxPriceUnpegRatio,
                Err.MAX_PRICE_UNPEG_RATIO
            );
            unchecked{++i;}
        }
    }

    function _tryGetTokenDecimals(address token) internal returns (uint8) {
        try IDecimals(token).decimals() returns (uint8 d) {
            return d;
        } catch {}
        return 0;
    }

}