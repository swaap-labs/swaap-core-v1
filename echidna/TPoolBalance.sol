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

import "../contracts/Pool.sol";
import "./MyToken.sol";
import "./CryticInterface.sol";
import "./TWBTCOracle.sol";

contract TPoolBalance is Pool, CryticInterface {

    MyToken public token;
    TWBTCOracle public oracle;
    
    uint internal initial_token_balance = type(uint).max;

    constructor() {
        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        token = new MyToken(initial_token_balance, address(this));
        
        // Create Oracle for each token
        oracle = new TWBTCOracle();

        // Bind the token with the minimal balance/weights
        bindMMM(address(token), Const.MIN_BALANCE, Const.MIN_WEIGHT, address(oracle));
        
        // Enable public swap 
        setPublicSwap(true);
    }

    function echidna_attacker_token_balance() public view returns(bool){
        // An attacker cannot obtain more tokens than its initial balance
        return token.balanceOf(crytic_attacker) == initial_token_balance/3; //initial balance of crytic_attacker
    }

    function echidna_pool_record_balance() public view returns (bool) {
        // If the token was unbinded, avoid revert and return true
        if (this.getNumTokens() == 0)
            return true; 
        // The token balance should not be out-of-sync
        return (token.balanceOf(address(this)) >= this.getBalance(address(token)));
    }
}
