// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/IERC1155BaseInternal.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {Assertions} from "../../Assertions.sol";
import {OptionPSFactory, IOptionPSFactory} from "contracts/mining/optionPS/OptionPSFactory.sol";
import {IOptionPS} from "contracts/mining/optionPS/IOptionPS.sol";
import {OptionPS} from "contracts/mining/optionPS/OptionPS.sol";
import {OptionPSStorage} from "contracts/mining/optionPS/OptionPSStorage.sol";

abstract contract OptionPSTest is Assertions, Test {
    OptionPSFactory internal optionPSFactory;

    OptionPS internal option;

    ERC20Mock internal base;
    ERC20Mock internal quote;
    bool internal isCall;

    UD60x18 internal strike;
    uint64 internal maturity;

    address internal underwriter;
    address internal otherUnderwriter;
    address internal longReceiver;
    address internal feeReceiver;

    uint256 internal initialBaseBalance;
    uint256 internal initialQuoteBalance;

    function setUp() public virtual {
        strike = ud(10e18);
        maturity = uint64(8 hours);
        initialBaseBalance = 100e18;
        initialQuoteBalance = 1000e6;

        underwriter = vm.addr(1);
        otherUnderwriter = vm.addr(2);
        longReceiver = vm.addr(3);
        feeReceiver = vm.addr(4);

        address optionPSFactoryImpl = address(new OptionPSFactory());
        address optionPSFactoryProxy = address(new ProxyUpgradeableOwnable(optionPSFactoryImpl));
        optionPSFactory = OptionPSFactory(optionPSFactoryProxy);

        address optionPSImpl = address(new OptionPS(feeReceiver));
        optionPSFactory.setManagedProxyImplementation(optionPSImpl);

        base = new ERC20Mock("WETH", 18);
        quote = new ERC20Mock("USDC", 6);
    }

    function _mintTokensAndApprove() internal {
        address[3] memory users = [underwriter, otherUnderwriter, longReceiver];

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);

            base.mint(users[i], initialBaseBalance);
            base.approve(address(option), initialBaseBalance);

            quote.mint(users[i], initialQuoteBalance);
            quote.approve(address(option), initialQuoteBalance);

            vm.stopPrank();
        }
    }

    function _longTokenId() internal view returns (uint256) {
        return OptionPSStorage.formatTokenId(IOptionPS.TokenType.Long, maturity, strike);
    }

    function _longExercisedTokenId() internal view returns (uint256) {
        return OptionPSStorage.formatTokenId(IOptionPS.TokenType.LongExercised, maturity, strike);
    }

    function _shortTokenId() internal view returns (uint256) {
        return OptionPSStorage.formatTokenId(IOptionPS.TokenType.Short, maturity, strike);
    }

    function test_deployProxy_RevertIf_ProxyAlreadyDeployed() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionPSFactory.OptionPSFactory__ProxyAlreadyDeployed.selector, address(option))
        );
        optionPSFactory.deployProxy(
            IOptionPSFactory.OptionPSArgs({base: address(base), quote: address(quote), isCall: isCall})
        );
    }

    function test_getSettings_ReturnExpectedValue() public {
        (address _base, address _quote, bool _isCall) = option.getSettings();
        assertEq(_base, address(base));
        assertEq(_quote, address(quote));
        assertEq(_isCall, isCall);
    }

    function test_underwrite_Success() public {
        vm.startPrank(underwriter);

        option.underwrite(strike, maturity, longReceiver, ud(1e18));
        assertEq(base.balanceOf(underwriter), isCall ? initialBaseBalance - 1e18 : initialBaseBalance);
        assertEq(base.balanceOf(address(option)), isCall ? 1e18 : 0);
        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6);
        assertEq(quote.balanceOf(address(option)), isCall ? 0 : 10e6);
        assertEq(option.balanceOf(underwriter, _shortTokenId()), 1e18);
        assertEq(option.balanceOf(longReceiver, _longTokenId()), 1e18);
    }

    function test_underwrite_RevertIf_OptionExpired() public {
        vm.warp(maturity + 1);

        vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionExpired.selector, maturity));
        option.underwrite(strike, maturity, longReceiver, ud(1e18));
    }

    function test_underwrite_RevertIf_MaturityNot8UTC() public {
        vm.startPrank(underwriter);

        uint256[5] memory timestamps = [
            uint256(1 days),
            uint256(1 days + 1536),
            uint256(1 days + 8 hours + 1),
            uint256(1 days + 8 hours - 1),
            uint256(1 days + 16 hours)
        ];

        for (uint256 i; i < timestamps.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionMaturityNot8UTC.selector, timestamps[i]));
            option.underwrite(ud(1e18), uint64(timestamps[i]), longReceiver, ud(1e18));
        }
    }

    function test_underwrite_RevertIf_StrikeInvalid() public {
        // prettier-ignore
        UD60x18[2][7] memory values = [
            [ud(1.11e18),    ud(0.1e18)],
            [ud(7.4e18),     ud(0.5e18)],
            [ud(10.5e18),    ud(1e18)],
            [ud(45.5e18),    ud(1e18)],
            [ud(54e18),      ud(5e18)],
            [ud(99e18),      ud(5e18)],
            [ud(101e18),     ud(10e18)]
        ];

        for (uint256 i; i < values.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOptionPS.OptionPS__StrikeNotMultipleOfStrikeInterval.selector,
                    values[i][0],
                    values[i][1]
                )
            );
            option.underwrite(values[i][0], uint64(8 hours), longReceiver, ud(1e18));
        }
    }

    function test_annihilate_Success() public {
        vm.startPrank(underwriter);

        option.underwrite(strike, maturity, underwriter, ud(1e18));
        assertEq(base.balanceOf(underwriter), isCall ? initialBaseBalance - 1e18 : initialBaseBalance);
        assertEq(base.balanceOf(address(option)), isCall ? 1e18 : 0);
        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6);
        assertEq(quote.balanceOf(address(option)), isCall ? 0 : 10e6);
        assertEq(option.balanceOf(underwriter, _shortTokenId()), 1e18);
        assertEq(option.balanceOf(underwriter, _longTokenId()), 1e18);

        option.annihilate(strike, maturity, ud(0.3e18));
        assertEq(base.balanceOf(underwriter), isCall ? initialBaseBalance - 1e18 + 0.3e18 : initialBaseBalance);
        assertEq(base.balanceOf(address(option)), isCall ? 1e18 - 0.3e18 : 0);
        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6 + 3e6);
        assertEq(quote.balanceOf(address(option)), isCall ? 0 : 10e6 - 3e6);
        assertEq(option.balanceOf(underwriter, _shortTokenId()), 1e18 - 0.3e18);
        assertEq(option.balanceOf(underwriter, _longTokenId()), 1e18 - 0.3e18);
    }

    function test_annihilate_RevertIf_OptionExpired() public {
        vm.warp(maturity + 1);

        vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionExpired.selector, maturity));
        option.annihilate(strike, maturity, ud(1e18));
    }

    function test_annihilate_RevertIf_NotEnoughLongs() public {
        vm.startPrank(underwriter);

        option.underwrite(strike, maturity, underwriter, ud(1e18));
        option.safeTransferFrom(underwriter, longReceiver, _longTokenId(), 0.1e18, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155BaseInternal.ERC1155Base__BurnExceedsBalance.selector));
        option.annihilate(strike, maturity, ud(1e18));
    }

    function test_annihilate_RevertIf_NotEnoughShorts() public {
        vm.startPrank(underwriter);

        option.underwrite(strike, maturity, underwriter, ud(1e18));
        option.safeTransferFrom(underwriter, longReceiver, _shortTokenId(), 0.1e18, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155BaseInternal.ERC1155Base__BurnExceedsBalance.selector));
        option.annihilate(strike, maturity, ud(1e18));
    }

    function test_exercise_Success() public {
        vm.prank(underwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        assertEq(quote.balanceOf(feeReceiver), 0);

        vm.prank(longReceiver);
        option.exercise(strike, maturity, ud(0.3e18));

        uint256 fee = isCall ? (3e6 * 0.003e18) / 1e18 : (0.3e18 * 0.003e18) / 1e18;

        assertEq(option.balanceOf(longReceiver, _longTokenId()), 0.7e18, "a");
        assertEq(option.balanceOf(longReceiver, _longExercisedTokenId()), 0.3e18, "b");

        assertEq(base.balanceOf(underwriter), isCall ? initialBaseBalance - 1e18 : initialBaseBalance, "c");
        assertEq(base.balanceOf(longReceiver), isCall ? initialBaseBalance : initialBaseBalance - 0.3e18 - fee, "d");
        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6, "e");
        assertEq(quote.balanceOf(longReceiver), isCall ? initialQuoteBalance - 3e6 - fee : initialQuoteBalance, "f");
        assertEq(base.balanceOf(address(option)), isCall ? 1e18 : 0.3e18, "g");
        assertEq(quote.balanceOf(address(option)), isCall ? 3e6 : 10e6, "h");
        assertEq(quote.balanceOf(feeReceiver), isCall ? fee : 0, "i");
        assertEq(base.balanceOf(feeReceiver), isCall ? 0 : fee, "j");
    }

    function test_settleLong_Success() public {
        vm.prank(underwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        assertEq(quote.balanceOf(feeReceiver), 0);

        vm.prank(longReceiver);
        option.exercise(strike, maturity, ud(0.3e18));

        vm.warp(maturity + 1);

        vm.prank(longReceiver);
        option.settleLong(strike, maturity, ud(0.3e18));

        uint256 fee = isCall ? (3e6 * 0.003e18) / 1e18 : (0.3e18 * 0.003e18) / 1e18;

        assertEq(base.balanceOf(underwriter), isCall ? initialBaseBalance - 1e18 : initialBaseBalance);
        assertEq(
            base.balanceOf(longReceiver),
            isCall ? initialBaseBalance + 0.3e18 : initialBaseBalance - 0.3e18 - fee
        );
        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6);
        assertEq(quote.balanceOf(longReceiver), isCall ? initialQuoteBalance - 3e6 - fee : initialQuoteBalance + 3e6);
        assertEq(base.balanceOf(address(option)), isCall ? 0.7e18 : 0.3e18);
        assertEq(quote.balanceOf(address(option)), isCall ? 3e6 : 7e6);
        assertEq(quote.balanceOf(feeReceiver), isCall ? fee : 0);
        assertEq(base.balanceOf(feeReceiver), isCall ? 0 : fee);
    }

    function test_exercise_RevertIf_OptionExpired() public {
        vm.warp(maturity + 1);
        vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionExpired.selector, maturity));
        option.exercise(strike, maturity, ud(1e18));
    }

    function test_cancelExercise_Success() public {
        vm.prank(underwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        assertEq(quote.balanceOf(feeReceiver), 0);

        uint256 fee = isCall ? (3e6 * 0.003e18) / 1e18 : (0.3e18 * 0.003e18) / 1e18;

        vm.startPrank(longReceiver);
        option.exercise(strike, maturity, ud(0.3e18));

        option.cancelExercise(strike, maturity, ud(0.2e18));

        assertEq(option.balanceOf(underwriter, _longTokenId()), 0, "a");
        assertEq(option.balanceOf(underwriter, _longExercisedTokenId()), 0, "b");
        assertEq(option.balanceOf(underwriter, _shortTokenId()), 1e18, "c");

        assertEq(option.balanceOf(longReceiver, _longTokenId()), 0.9e18, "d");
        assertEq(option.balanceOf(longReceiver, _longExercisedTokenId()), 0.1e18, "e");
        assertEq(option.balanceOf(longReceiver, _shortTokenId()), 0, "f");

        assertEq(quote.balanceOf(underwriter), isCall ? initialQuoteBalance : initialQuoteBalance - 10e6, "g");
        assertEq(quote.balanceOf(longReceiver), isCall ? initialQuoteBalance - 1e6 - fee : initialQuoteBalance, "h");

        assertEq(quote.balanceOf(feeReceiver), isCall ? fee : 0, "i");
        assertEq(base.balanceOf(feeReceiver), isCall ? 0 : fee, "j");
    }

    function test_cancelExercise_RevertIf_OptionExpired() public {
        vm.warp(maturity + 1);
        vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionExpired.selector, maturity));
        option.cancelExercise(strike, maturity, ud(1e18));
    }

    function test_settleShort_Success() public {
        vm.prank(underwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        vm.prank(otherUnderwriter);
        option.underwrite(strike, maturity, longReceiver, ud(3e18));

        vm.prank(longReceiver);
        option.exercise(strike, maturity, ud(3e18));

        vm.warp(maturity + 1);
        vm.prank(longReceiver);
        option.settleLong(strike, maturity, ud(3e18));

        uint256 fee = isCall ? (30e6 * 0.003e18) / 1e18 : (3e18 * 0.003e18) / 1e18;

        vm.warp(maturity + 1);

        vm.prank(underwriter);
        option.settleShort(strike, maturity, ud(1e18));

        vm.prank(otherUnderwriter);
        option.settleShort(strike, maturity, ud(3e18));

        assertEq(option.balanceOf(longReceiver, _longTokenId()), 1e18);
        assertEq(option.totalSupply(_longTokenId()), 1e18);
        assertEq(option.totalSupply(_shortTokenId()), 0);

        assertEq(
            base.balanceOf(underwriter),
            isCall ? initialBaseBalance - 1e18 + 0.25e18 : initialBaseBalance + (3e18 / 4)
        ); // CALL : initial - 1 + 1 * 1/4 | PUT : initial + 3 * 1/4
        assertEq(
            base.balanceOf(otherUnderwriter),
            isCall ? initialBaseBalance - 3e18 + 0.75e18 : initialBaseBalance + ((3e18 * 3) / 4)
        ); // CALL : initial - 3 + 1 * 3/4 | PUT : initial + 3 * 3/4
        assertEq(base.balanceOf(longReceiver), isCall ? initialBaseBalance + 3e18 : initialBaseBalance - 3e18 - fee); // CALL : initial + 3 | PUT : initial  - 0.3 - fee

        assertEq(
            quote.balanceOf(underwriter),
            isCall ? initialQuoteBalance + 30e6 / 4 : initialQuoteBalance - 10e6 + 10e6 / 4
        ); // CALL : initial + 30 * 1/4 | PUT : initial - 10 + 10 * 1/4
        assertEq(
            quote.balanceOf(otherUnderwriter),
            isCall ? initialQuoteBalance + (30e6 * 3) / 4 : initialQuoteBalance - 30e6 + (10e6 * 3) / 4
        ); // initial + 30 * 3/4 | PUT : initial - 30 + 10 * 3/4
        assertEq(quote.balanceOf(longReceiver), isCall ? initialQuoteBalance - 30e6 - fee : initialQuoteBalance + 30e6); // initial - 30 - fee | PUT : initial  + 30

        assertEq(base.balanceOf(feeReceiver), isCall ? 0 : fee);
        assertEq(quote.balanceOf(feeReceiver), isCall ? fee : 0);
    }

    function test_settleShort_RevertIf_OptionNotExpired() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionPS.OptionPS__OptionNotExpired.selector, maturity));
        option.settleShort(strike, maturity, ud(1e18));
    }

    function test_getTokenIds_ReturnExpectedValue() public {
        uint256[] memory tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 0);

        vm.prank(underwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        uint256 firstLongTokenId = _longTokenId();
        uint256 firstShortTokenId = _shortTokenId();

        tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], firstLongTokenId);
        assertEq(tokenIds[1], firstShortTokenId);

        maturity += 1 days;
        vm.prank(otherUnderwriter);
        option.underwrite(strike, maturity, longReceiver, ud(1e18));

        tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 4);
        assertEq(tokenIds[0], firstLongTokenId);
        assertEq(tokenIds[1], firstShortTokenId);
        assertEq(tokenIds[2], _longTokenId());
        assertEq(tokenIds[3], _shortTokenId());

        vm.prank(longReceiver);
        option.safeTransferFrom(longReceiver, underwriter, firstLongTokenId, 1e18, "");

        vm.prank(longReceiver);
        option.safeTransferFrom(longReceiver, otherUnderwriter, _longTokenId(), 1e18, "");

        tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 4);
        assertEq(tokenIds[0], firstLongTokenId);
        assertEq(tokenIds[1], firstShortTokenId);
        assertEq(tokenIds[2], _longTokenId());
        assertEq(tokenIds[3], _shortTokenId());

        vm.prank(underwriter);
        option.annihilate(strike, maturity - 1 days, ud(1e18));

        tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], _shortTokenId());
        assertEq(tokenIds[1], _longTokenId());

        vm.prank(otherUnderwriter);
        option.annihilate(strike, maturity, ud(1e18));

        tokenIds = option.getTokenIds();
        assertEq(tokenIds.length, 0);
    }
}
