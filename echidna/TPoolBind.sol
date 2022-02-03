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

import "./contracts/Pool.sol";
import "./MyToken.sol";
import "./CryticInterface.sol";
import "./contracts/test/TWBTCOracle.sol";
import "./contracts/test/TWETHOracle.sol";


contract TPoolBindPrivileged is CryticInterface, Pool {

    TWBTCOracle oracle;

    constructor() {
        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        MyToken t;
        t = new MyToken(initial_token_balance, address(this));
        // Create Oracle for the initial token
        oracle = new TWBTCOracle(block.timestamp);
        // Bind the token with the provided parameters
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

    function echidna_getNumTokens_less_or_equal_MAX_BOUND_TOKENS() public view returns (bool) {
        // it is not possible to bind more than `MAX_BOUND_TOKENS` 
        return this.getNumTokens() <= Const.MAX_BOUND_TOKENS;
    }

    function echidna_revert_bind_twice() public returns (bool) {
        if (this.getCurrentTokens().length > 0 && this.getController() == crytic_owner && !this.isFinalized()) {
            // binding the first token should be enough, if we have this property to always revert
            bindMMM(this.getCurrentTokens()[0], valid_balance_to_bind, valid_denorm_to_bind, address(oracle));
            // This return will make this property to fail
            return true;
        }
        // If there are no tokens or if the controller was changed or if the pool was finalized, just revert.
        revert();
    }

    function echidna_revert_unbind_twice() public returns (bool) {
        if (this.getCurrentTokens().length > 0 && this.getController() == crytic_owner && !this.isFinalized()) {
            address[] memory current_tokens = this.getCurrentTokens();
            // unbinding the first token twice should be enough, if we want this property to always revert
            unbindMMM(current_tokens[0]);
            unbindMMM(current_tokens[0]);
            return true;
        }
        // if there are no tokens or if the controller was changed or if the pool was finalized, just revert
        revert();
    }

    function echidna_all_tokens_are_unbindable() public returns (bool) {
        if (this.getController() == crytic_owner && !this.isFinalized()) {
            address[] memory current_tokens = this.getCurrentTokens();
            // unbind all the tokens, one by one
            for (uint i = 0; i < current_tokens.length; i++) {
                unbindMMM(current_tokens[i]);
            }
            // at the end, the list of current tokens should be empty
            return (this.getCurrentTokens().length == 0);
        }

        // if the controller was changed or if the pool was finalized, just return true
        return true;
    }

    function echidna_all_tokens_are_rebindable_with_valid_parameters() public returns (bool) {
        if (this.getController() == crytic_owner && !this.isFinalized()) {
            address[] memory current_tokens = this.getCurrentTokens();
            for (uint i = 0; i < current_tokens.length; i++) {
                // rebind all the tokens, one by one, using valid parameters
                uint256 oldWeight = this.getDenormalizedWeight(current_tokens[i]);
                rebindMMM(current_tokens[i], valid_balance_to_bind, oldWeight, address(oracle));
            }
            // at the end, the list of current tokens should have not change in size
            return current_tokens.length == this.getCurrentTokens().length;
        }
        // if the controller was changed or if the pool was finalized, just return true 
        return true;
    }

    function echidna_revert_rebind_unbinded() public returns (bool) {
        if (this.getCurrentTokens().length > 0 && this.getController() == crytic_owner && !this.isFinalized()) {
            address[] memory current_tokens = this.getCurrentTokens();
            // unbinding and rebinding the first token should be enough, if we want this property to always revert
            unbindMMM(current_tokens[0]);
            rebindMMM(current_tokens[0], valid_balance_to_bind, valid_denorm_to_bind, address(oracle));
            return true;
        }
        // if the controller was changed or if the pool was finalized, just return true  
        revert();
    }
}

contract TPoolBindUnprivileged is CryticInterface, Pool {

    MyToken t1;
    MyToken t2;
    TWBTCOracle oracle1;
    TWETHOracle oracle2;
    // initial token balances is the max amount for uint256
    uint internal initial_token_balance = type(uint).max;
 
    constructor() {
        // Create Oracle for each token
        oracle1 = new TWBTCOracle(block.timestamp);
        oracle2 = new TWETHOracle(block.timestamp);

        // two tokens with minimal balances and weights are created by the controller
        t1 = new MyToken(initial_token_balance, address(this));
        bindMMM(address(t1), Const.MIN_BALANCE, Const.MIN_WEIGHT, address(oracle1));
        t2 = new MyToken(initial_token_balance, address(this));
        bindMMM(address(t2), Const.MIN_BALANCE, Const.MIN_WEIGHT, address(oracle2));
    }
   
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
        TWBTCOracle oracleBT = new TWBTCOracle(block.timestamp);
        // Bind the token with the provided parameters
        bindMMM(address(bt), balance, denorm, address(oracleBT));
        // Save the balance and denorm values used. These are used in the rebind checks
        valid_balance_to_bind = balance;
        valid_denorm_to_bind = denorm;
        return address(bt);
    }

    function echidna_only_controller_can_bind() public view returns (bool) {
        // the number of tokens cannot be changed
        return this.getNumTokens() == 2;
    }

    function echidna_revert_when_bind() public returns (bool) {
         // calling bind will revert
         create_and_bind(valid_balance_to_bind, valid_denorm_to_bind); 
         return true;
    } 

    function echidna_revert_when_rebind() public returns (bool) {
          // calling rebind on binded tokens will revert
          rebindMMM(address(t1), valid_balance_to_bind, valid_denorm_to_bind, address(oracle1));
          rebindMMM(address(t2), valid_balance_to_bind, valid_denorm_to_bind, address(oracle2));
          return true;
    }

    function echidna_revert_when_unbind() public returns (bool) {
          // calling unbind on binded tokens will revert 
          unbindMMM(address(t1));
          unbindMMM(address(t2));
          return true;
    }  
}
