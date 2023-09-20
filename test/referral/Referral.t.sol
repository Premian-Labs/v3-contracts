// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {IReferral} from "contracts/referral/IReferral.sol";

import {Base_Test} from "../Base.t.sol";

/*//////////////////////////////////////////////////////////////////////////
                  Shared Tests
//////////////////////////////////////////////////////////////////////////*/
abstract contract Referral_Integration_Shared_Test is Base_Test {
    // Test contracts
    IPoolMock internal pool;

    // Variables
    IPoolFactory.PoolKey internal poolKey;

    UD60x18 internal tradingFee = ud(200e18);
    UD60x18 internal primaryRebate = ud(10e18);
    UD60x18 internal secondaryRebate = ud(1e18);
    UD60x18 internal totalRebate = primaryRebate + secondaryRebate;

    address internal constant secondaryReferrer = address(0x999);

    function setUp() public virtual override {
        super.setUp();

        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: 1_682_668_800,
            isCallPool: true
        });

        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
    }

    function getStartTimestamp() internal virtual override returns (uint256) {
        return 1_679_758_940;
    }

    /*//////////////////////////////////////////////////////////////////////////
                      Helpers
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function toTokenDecimals(address token, UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(token).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(address token, uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = ISolidStateERC20(token).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }
}

/*//////////////////////////////////////////////////////////////////////////
                  Integration Tests
//////////////////////////////////////////////////////////////////////////*/
contract Referral_Integration_Concrete_Test is Referral_Integration_Shared_Test {
    /*//////////////////////////////////////////////////////////////////////////
                          setPrimaryRebatePercent
    //////////////////////////////////////////////////////////////////////////*/
    function test_setPrimaryRebatePercent_Success() public {
        UD60x18 percent = ud(100e18);

        changePrank(users.deployer);
        referral.setPrimaryRebatePercent(percent, IReferral.RebateTier.PrimaryRebate1);

        (UD60x18[] memory primaryRebatePercents, ) = referral.getRebatePercents();

        assertEq(primaryRebatePercents[0], percent);
    }

    function test_setPrimaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        changePrank(users.trader);

        referral.setPrimaryRebatePercent(ud(100e18), IReferral.RebateTier.PrimaryRebate1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                      setPrimaryRebatePercent
    //////////////////////////////////////////////////////////////////////////*/
    function test_setSecondaryRebatePercent_Success() public {
        changePrank(users.deployer);

        UD60x18 percent = ud(100e18);

        referral.setSecondaryRebatePercent(percent);

        (, UD60x18 secondaryRebatePercent) = referral.getRebatePercents();

        assertEq(secondaryRebatePercent, percent);
    }

    function test_setSecondaryRebatePercent_RevertIf_Not_Owner() public {
        changePrank(users.trader);

        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        referral.setSecondaryRebatePercent(ud(100e18));
    }

    /*//////////////////////////////////////////////////////////////////////////
                          setRebateTier
    //////////////////////////////////////////////////////////////////////////*/
    function test_setRebateTier_RevertIf_Not_Owner() public {
        changePrank(users.trader);

        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);
    }

    function test_setRebateTier_Success() public {
        changePrank(users.deployer);

        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate1));

        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);

        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate2));
    }

    /*//////////////////////////////////////////////////////////////////////////
                          internal_trySetReferrer
    //////////////////////////////////////////////////////////////////////////*/
    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Not_Set() public {
        changePrank(users.trader);

        address referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, address(0));
        assertEq(referral.getReferrer(users.trader), address(0));
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Not_Set() public {
        changePrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Set() public {
        changePrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, users.referrer);
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Set() public {
        changePrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(secondaryReferrer);
        assertEq(referrer, users.referrer);

        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    /*//////////////////////////////////////////////////////////////////////////
                          useReferral
    //////////////////////////////////////////////////////////////////////////*/
    function test_useReferral_RevertIf_Pool_Not_Authorized() public {
        changePrank(users.trader);
        vm.expectRevert(IReferral.Referral__PoolNotAuthorized.selector);

        referral.useReferral(users.trader, users.referrer, address(0), ud(0), ud(0));
    }

    /*//////////////////////////////////////////////////////////////////////////
                          getRebateAmounts
    //////////////////////////////////////////////////////////////////////////*/
    function test_getRebateAmounts_Success() public {
        changePrank(users.trader);
        (UD60x18 _primaryRebate, UD60x18 _secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            address(0),
            tradingFee
        );

        UD60x18 _totalRebate = _primaryRebate + _secondaryRebate;

        assertEq(_totalRebate, ZERO);
        assertEq(_primaryRebate, ZERO);
        assertEq(_secondaryRebate, ZERO);

        (_primaryRebate, _secondaryRebate) = referral.getRebateAmounts(users.trader, users.referrer, tradingFee);
        _totalRebate = _primaryRebate + _secondaryRebate;
        assertEq(_totalRebate, primaryRebate);
        assertEq(_primaryRebate, primaryRebate);
        assertEq(_secondaryRebate, ZERO);

        referral.__trySetReferrer(users.referrer);

        (_primaryRebate, _secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), tradingFee);
        _totalRebate = _primaryRebate + _secondaryRebate;
        assertEq(_totalRebate, primaryRebate);
        assertEq(_primaryRebate, primaryRebate);
        assertEq(_secondaryRebate, ZERO);

        changePrank({msgSender: users.referrer});
        referral.__trySetReferrer(secondaryReferrer);

        changePrank({msgSender: users.trader});
        (_primaryRebate, _secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), tradingFee);
        _totalRebate = _primaryRebate + _secondaryRebate;
        assertEq(_totalRebate, totalRebate);
        assertEq(_primaryRebate, primaryRebate);
        assertEq(_secondaryRebate, secondaryRebate);
    }
}

contract Referral_UseReferral_Integration_Concrete_Test is Referral_Integration_Shared_Test {
    // Test contracts
    ERC20Mock internal fake;

    // Variables
    uint256 internal primaryRebate0;
    uint256 internal secondaryRebate0;
    uint256 internal primaryRebate1;
    uint256 internal secondaryRebate1;

    function setUp() public virtual override {
        super.setUp();

        // Mint fake token for referral contract
        fake = new ERC20Mock("MOCK", 18);
        uint256 referrerFakeBefore = 1000e18;
        fake.mint(address(referral), referrerFakeBefore);

        // Use referral rebate with `base`
        (primaryRebate0, secondaryRebate0) = useReferralSetup(200e18, base);

        // Use referral rebate with `quote`
        (primaryRebate1, secondaryRebate1) = useReferralSetup(100e18, quote);
    }

    function useReferralSetup(uint256 fee, ERC20Mock token) internal returns (uint256, uint256) {
        changePrank(users.referrer);

        referral.__trySetReferrer(secondaryReferrer);

        changePrank(address(pool));
        deal(address(token), address(pool), fee);

        (UD60x18 _primaryRebate, UD60x18 _secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            users.referrer,
            fromTokenDecimals(address(token), fee)
        );

        UD60x18 _totalRebate = _primaryRebate + _secondaryRebate;

        token.approve(address(referral), toTokenDecimals(address(token), _totalRebate));

        referral.useReferral(users.trader, users.referrer, address(token), _primaryRebate, _secondaryRebate);

        assertEq(referral.getReferrer(users.trader), users.referrer);
        assertEq(token.balanceOf(address(pool)), fee - toTokenDecimals(address(token), _totalRebate));
        assertEq(token.balanceOf(address(referral)), toTokenDecimals(address(token), _totalRebate));

        return (toTokenDecimals(address(token), _primaryRebate), toTokenDecimals(address(token), _secondaryRebate));
    }

    /*//////////////////////////////////////////////////////////////////////////
                      claimRebate
    //////////////////////////////////////////////////////////////////////////*/
    function test_claimRebate_Success() public {
        uint256 referralFakeBefore = fake.balanceOf(address(referral));
        uint256 referrerBaseBefore = base.balanceOf(users.referrer);
        uint256 referrerQuoteBefore = quote.balanceOf(users.referrer);

        {
            address[] memory tokens = new address[](3);
            tokens[0] = address(fake);
            tokens[1] = address(base);
            tokens[2] = address(quote);

            changePrank(users.referrer);
            referral.claimRebate(tokens);

            changePrank(secondaryReferrer);
            referral.claimRebate(tokens);
        }

        assertEq(fake.balanceOf(address(referral)), referralFakeBefore);
        assertEq(base.balanceOf(address(referral)), 0);
        assertEq(quote.balanceOf(address(referral)), 0);

        assertEq(fake.balanceOf(users.referrer), 0);
        assertEq(fake.balanceOf(secondaryReferrer), 0);

        assertEq(base.balanceOf(users.referrer), referrerBaseBefore + primaryRebate0);
        assertEq(base.balanceOf(secondaryReferrer), secondaryRebate0);

        assertEq(quote.balanceOf(users.referrer), referrerQuoteBefore + primaryRebate1);
        assertEq(quote.balanceOf(secondaryReferrer), secondaryRebate1);

        {
            (address[] memory tokens, uint256[] memory rebates) = referral.getRebates(users.referrer);

            assertEq(tokens.length, 0);
            assertEq(rebates.length, 0);

            (tokens, rebates) = referral.getRebates(secondaryReferrer);

            assertEq(tokens.length, 0);
            assertEq(rebates.length, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                  getRebates
    //////////////////////////////////////////////////////////////////////////*/
    function test_getRebates_Success() public {
        (address[] memory tokens, uint256[] memory rebates) = referral.getRebates(users.referrer);

        assertEq(tokens[0], address(base));
        assertEq(rebates[0], primaryRebate0);

        assertEq(tokens[1], address(quote));
        assertEq(rebates[1], primaryRebate1);

        (tokens, rebates) = referral.getRebates(secondaryReferrer);

        assertEq(tokens[0], address(base));
        assertEq(rebates[0], secondaryRebate0);

        assertEq(tokens[1], address(quote));
        assertEq(rebates[1], secondaryRebate1);
    }
}
