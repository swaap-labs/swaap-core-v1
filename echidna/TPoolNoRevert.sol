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


contract TPoolNoRevert is CryticInterface, Pool {

    TWBTCOracle oracle;

    constructor() {

        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        MyToken t;
        t = new MyToken(initial_token_balance, address(this));

        // Create Oracle for the initial token
        oracle = new TWBTCOracle();

        // Bind the token with the provided parameters
        bindMMM(address(t), Const.MIN_BALANCE, Const.MIN_WEIGHT, address(oracle));

    }

    // initial token balances is the max amount for uint256
    uint internal initial_token_balance = type(uint).max;

    // this function allows to create as many tokens as needed
    function create_and_bind(uint balance, uint denorm) public returns (address) {
        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        MyToken bt = new MyToken(initial_token_balance, address(this));
        bt.approve(address(this), initial_token_balance);
        // Create Oracle for the buy token
        TWETHOracle oracleBT = new TWETHOracle();
        // Bind the token with the provided parameters
        bindMMM(address(bt), balance, denorm, address(oracleBT));
        // Save the balance and denorm values used. These are used in the rebind checks
        return address(bt);
    }
    
    function echidna_getSpotPrice_no_revert() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
            for (uint j = 0; j < current_tokens.length; j++) {
                // getSpotPrice should not revert for any pair of tokens
                this.getSpotPriceMMM(address(current_tokens[i]), address(current_tokens[j]));
            }
        }

       return true;
    }

    function echidna_getSpotPriceSansFee_no_revert() public view returns (bool) {
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
            for (uint j = 0; j < current_tokens.length; j++) {
                // getSpotPriceSansFee should not revert for any pair of tokens
                this.getSpotPriceSansFeeMMM(address(current_tokens[i]), address(current_tokens[j]));
            }
        }

       return true;
    }

    function echidna_swapExactAmountIn_no_revert() public returns (bool) {
        // if the controller was changed, return true
        if (this.getController() != crytic_owner)
            return true;

        // if the pool was not finalized, enable the public swap
        if (!this.isFinalized())
            setPublicSwap(true);
 
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++) {
            // a small balance is 1% of the total balance available
            uint small_balance = this.getBalance(current_tokens[i])/100; 
            // if the user has a small balance, it should be able to swap it
            if (IERC20(current_tokens[i]).balanceOf(crytic_owner) > small_balance)
               swapExactAmountInMMM(address(current_tokens[i]), small_balance, address(current_tokens[i]), 0, type(uint).max);
        }

        return true;
    }

}

