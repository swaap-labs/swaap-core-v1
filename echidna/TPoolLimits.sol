// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General internal License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General internal License for more details.

// You should have received a copy of the GNU General internal License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.0;

import "./contracts/Pool.sol";
import "./MyToken.sol";
import "./CryticInterface.sol";
import "./contracts/test/TWBTCOracle.sol";
import "./contracts/test/TWETHOracle.sol";


contract TPoolLimits is CryticInterface, Pool {

    uint MAX_BALANCE = Const.BONE * 10**12;
    TWBTCOracle oracle;

    constructor() {
        MyToken t;
        t = new MyToken(type(uint).max, address(this));
        oracle = new TWBTCOracle(block.timestamp);
        bindMMM(address(t), Const.MIN_BALANCE, Const.MIN_WEIGHT, address(oracle)); 
    }

    // initial token balances is the max amount for uint256
    uint internal initial_token_balance = type(uint).max;
    // these two variables are used to save valid balances and denorm parameters
    uint internal valid_balance_to_bind = Const.MIN_BALANCE;
    uint internal valid_denorm_to_bind = Const.MIN_WEIGHT;

    // this function allows to create as many tokens as needed
    function create_and_bind(uint balance, uint denorm) public returns (address) {
        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        MyToken bt = new MyToken(initial_token_balance, address(this));
        bt.approve(address(this), initial_token_balance); 
        // Create Oracle for the buy token
        TWETHOracle oracleBT = new TWETHOracle(block.timestamp);
        // Bind the token with the provided parameters
        bindMMM(address(bt), balance, denorm, address(oracleBT));
        // Save the balance and denorm values used. These are used in the rebind checks
        valid_balance_to_bind = balance;
        valid_denorm_to_bind = denorm;
        return address(bt);
    }

    function echidna_valid_weights() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        // store the normalized weight in this variable
        uint nw = 0;
        for (uint i = 0; i < current_tokens.length; i++) {
            // accumulate the total normalized weights, checking for overflows
            nw += this.getNormalizedWeight(current_tokens[i]);
        }
        // convert the sum of normalized weights into an integer
        nw = Num.btoi(nw);

        // if there are no tokens, check that the normalized weight is zero
        if (current_tokens.length == 0)
            return (nw == 0);

        // if there are tokens, the normalized weight should be 1
        return (nw == 1);
    }

    function echidna_min_token_balance() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
             // verify that the balance of each token is more than `MIN_BALACE` 
            if (this.getBalance(address(current_tokens[i])) < Const.MIN_BALANCE)
                return false;
        }
        // if there are no tokens, return true 
        return true;
    }

    function echidna_max_weight() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
            // verify that the weight of each token is less than `MAX_WEIGHT`  
            if (this.getDenormalizedWeight(address(current_tokens[i])) > Const.MAX_WEIGHT)
                return false;
        }
        // if there are no tokens, return true 
        return true;
    }

    function echidna_min_weight() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
            // verify that the weight of each token is more than `MIN_WEIGHT`  
            if (this.getDenormalizedWeight(address(current_tokens[i])) < Const.MIN_WEIGHT)
                return false;
        }
        // if there are no tokens, return true 
        return true;
    }


    function echidna_min_swap_free() public view returns (bool) {
        // verify that the swap fee is greater or equal than `MIN_FEE`
        return this.getSwapFee() >= Const.MIN_FEE;
    }

    function echidna_max_swap_free() public view returns (bool) {
        // verify that the swap fee is less or equal than `MAX_FEE`
        return this.getSwapFee() <= Const.MAX_FEE;
    }

    function echidna_revert_max_swapExactAmountOut() public returns (bool) {
        // if the controller was changed, revert
        if (this.getController() != crytic_owner)
            revert();

        // if the pool is not finalized, make sure public swap is enabled
        if (!this.isFinalized())
            setPublicSwap(true);

        address[] memory current_tokens = this.getCurrentTokens();
        // if there is not token, revert
        if (current_tokens.length == 0)
            revert();

        uint large_balance = this.getBalance(current_tokens[0])/3 + 2;

        // check that the balance is large enough
        if (IERC20(current_tokens[0]).balanceOf(crytic_owner) < large_balance)
            revert();

        // call swapExactAmountOutMMM with more than 1/3 of the balance should revert
        swapExactAmountOutMMM(address(current_tokens[0]), type(uint256).max, address(current_tokens[0]), large_balance, type(uint256).max);
        return true;
    }

    function echidna_revert_max_swapExactAmountIn() public returns (bool) {
        // if the controller was changed, revert
        if (this.getController() != crytic_owner)
           revert();

        // if the pool is not finalized, make sure public swap is enabled  
        if (!this.isFinalized())
           setPublicSwap(true);

        address[] memory current_tokens = this.getCurrentTokens();
        // if there is not token, revert
        if (current_tokens.length == 0)
            revert();

        uint large_balance = this.getBalance(current_tokens[0])/2 + 1;

        if (IERC20(current_tokens[0]).balanceOf(crytic_owner) < large_balance)
            revert();

        swapExactAmountInMMM(address(current_tokens[0]), large_balance, address(current_tokens[0]), 0, type(uint).max);

        return true;
    }

}
