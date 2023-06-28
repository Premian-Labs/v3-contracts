// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {IOptionReward} from "contracts/mining/optionReward/IOptionReward.sol";
import {OptionReward} from "contracts/mining/optionReward/OptionReward.sol";
import {IOptionRewardFactory} from "contracts/mining/optionReward/IOptionRewardFactory.sol";
import {OptionRewardStorage} from "contracts/mining/optionReward/OptionRewardStorage.sol";
import {OptionRewardFactory} from "contracts/mining/optionReward/OptionRewardFactory.sol";

import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";

import {PaymentSplitter} from "contracts/mining/PaymentSplitter.sol";

import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {IOptionPSFactory} from "contracts/mining/optionPS/IOptionPSFactory.sol";
import {OptionPSFactory} from "contracts/mining/optionPS/OptionPSFactory.sol";
import {IOptionPS} from "contracts/mining/optionPS/IOptionPS.sol";
import {OptionPS} from "contracts/mining/optionPS/OptionPS.sol";
import {OptionPSStorage} from "contracts/mining/optionPS/OptionPSStorage.sol";
import {IMiningAddRewards} from "contracts/mining/IMiningAddRewards.sol";

import {Assertions} from "../../Assertions.sol";

contract MiningMock is IMiningAddRewards {
    address internal immutable PREMIA;

    constructor(address premia) {
        PREMIA = premia;
    }

    function addRewards(uint256 amount) external {
        IERC20(PREMIA).transferFrom(msg.sender, address(this), amount);
    }
}

contract OptionRewardTest is Assertions, Test {
    uint256 internal constant exercisePeriod = 7 days;
    UD60x18 internal constant discount = UD60x18.wrap(0.55e18);
    UD60x18 internal constant penalty = UD60x18.wrap(0.75e18);
    uint256 internal constant optionDuration = 30 days;
    uint256 internal constant lockupDuration = 365 days;
    UD60x18 internal constant spot = UD60x18.wrap(1e18);
    UD60x18 internal constant fee = UD60x18.wrap(0.1e18);

    PaymentSplitter internal paymentSplitter;
    PriceRepository internal priceRepository;
    OptionPSFactory internal optionPSFactory;
    OptionReward internal optionReward;
    VxPremia internal vxPremia;
    OptionPS internal option;
    address internal mining;

    ERC20Mock internal base;
    ERC20Mock internal quote;

    UD60x18 internal _size;
    uint256 internal size;

    uint64 internal maturity;

    address internal underwriter;
    address internal otherUnderwriter;
    address internal longReceiver;
    address internal feeReceiver;
    address internal relayer;

    uint256 internal initialBaseBalance;
    uint256 internal initialQuoteBalance;

    function setUp() public {
        maturity = uint64(optionDuration + 8 hours);
        initialBaseBalance = 100e18;
        initialQuoteBalance = 1000e6;

        underwriter = vm.addr(1);
        otherUnderwriter = vm.addr(2);
        longReceiver = vm.addr(3);
        feeReceiver = vm.addr(4);
        relayer = vm.addr(5);

        address priceRepositoryImpl = address(new PriceRepository());
        address priceRepositoryProxy = address(new ProxyUpgradeableOwnable(priceRepositoryImpl));
        priceRepository = PriceRepository(priceRepositoryProxy);

        address optionPSFactoryImpl = address(new OptionPSFactory());
        address optionPSFactoryProxy = address(new ProxyUpgradeableOwnable(optionPSFactoryImpl));
        optionPSFactory = OptionPSFactory(optionPSFactoryProxy);

        address optionPSImpl = address(new OptionPS(feeReceiver));
        optionPSFactory.setManagedProxyImplementation(optionPSImpl);

        base = new ERC20Mock("PREMIA", 18);
        quote = new ERC20Mock("USDC", 6);

        size = 1000000e18;
        _size = ud(size);

        address vxPremiaImpl = address(new VxPremia(address(0), address(0), address(base), address(quote), address(0)));
        address vxPremiaProxy = address(new VxPremiaProxy(vxPremiaImpl));
        vxPremia = VxPremia(vxPremiaProxy);

        mining = address(new MiningMock(address(base)));

        paymentSplitter = new PaymentSplitter(base, quote, vxPremia, IMiningAddRewards(mining));

        PriceRepository implementation = new PriceRepository();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        priceRepository = PriceRepository(address(proxy));

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;
        priceRepository.addWhitelistedRelayers(relayers);

        OptionReward optionRewardImplementation = new OptionReward(feeReceiver, fee);
        address optionRewardFactoryImpl = address(new OptionRewardFactory());
        ProxyUpgradeableOwnable optionRewardFactoryProxy = new ProxyUpgradeableOwnable(optionRewardFactoryImpl);
        OptionRewardFactory optionRewardFactory = OptionRewardFactory(address(optionRewardFactoryProxy));
        optionRewardFactory.setManagedProxyImplementation(address(optionRewardImplementation));

        option = OptionPS(
            optionPSFactory.deployProxy(
                IOptionPSFactory.OptionPSArgs({base: address(base), quote: address(quote), isCall: true})
            )
        );

        IOptionRewardFactory.OptionRewardArgs memory args = IOptionRewardFactory.OptionRewardArgs({
            option: option,
            priceRepository: address(priceRepository),
            paymentSplitter: address(paymentSplitter),
            discount: discount,
            penalty: penalty,
            optionDuration: optionDuration,
            lockupDuration: lockupDuration
        });

        optionReward = OptionReward(optionRewardFactory.deployProxy(args));

        assertTrue(optionRewardFactory.isProxyDeployed(address(optionReward)));
        (address _optionReward, ) = optionRewardFactory.getProxyAddress(args);
        assertEq(address(optionReward), _optionReward);
    }

    function _setPriceAt(uint256 timestamp, UD60x18 price) internal {
        vm.prank(relayer);
        priceRepository.setPriceAt(address(base), address(quote), timestamp, price);
    }

    function _toTokenDecimals(address token, UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    function _test_underwrite_Success() internal returns (uint256 collateral) {
        //

        _setPriceAt(block.timestamp, spot);

        collateral = _toTokenDecimals(address(base), _size);
        base.mint(underwriter, collateral);

        vm.startPrank(underwriter);
        base.approve(address(optionReward), collateral);
        optionReward.underwrite(longReceiver, _size);
        vm.stopPrank();
    }

    function test_underwrite_Success() public {
        uint256 collateral = _test_underwrite_Success();

        UD60x18 strike = discount * spot;
        uint256 longTokenId = OptionPSStorage.formatTokenId(IOptionPS.TokenType.Long, maturity, strike);
        uint256 shortTokenId = OptionPSStorage.formatTokenId(IOptionPS.TokenType.Short, maturity, strike);

        assertEq(option.balanceOf(longReceiver, longTokenId), size);
        assertEq(option.balanceOf(longReceiver, shortTokenId), 0);
        assertEq(option.balanceOf(address(optionReward), shortTokenId), size);
        assertEq(option.balanceOf(address(optionReward), longTokenId), 0);

        assertEq(base.balanceOf(underwriter), 0);
        assertEq(base.balanceOf(address(option)), collateral);
    }

    event Underwrite(address indexed user, UD60x18 strike, uint64 maturity, UD60x18 contractSize);

    function test_underwrite_CorrectMaturity() public {
        uint256 collateral = _toTokenDecimals(address(base), ud(100e18));
        base.mint(underwriter, collateral);

        vm.prank(underwriter);
        base.approve(address(optionReward), collateral);

        vm.warp(1682155823); // Apr-22-2023 09:30:23 AM +UTC
        _setPriceAt(block.timestamp, ONE);
        uint256 timestamp8AMUTC = 1682150400; // Apr-22-2023 08:00:00 AM +UTC
        uint256 expectedMaturity = timestamp8AMUTC + 30 days; // May-22-2023 08:00:00 AM +UTC

        vm.expectEmit();
        emit Underwrite(underwriter, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);

        vm.warp(1682207999); // Apr-22-2023 23:59:59 PM +UTC

        expectedMaturity = timestamp8AMUTC + optionDuration; // May-22-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit Underwrite(underwriter, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);

        vm.warp(1682208000); // Apr-23-2023 00:00:00 AM +UTC

        timestamp8AMUTC = 1682236800; // Apr-23-2023 08:00:00 AM +UTC
        expectedMaturity = timestamp8AMUTC + optionDuration; // May-23-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit Underwrite(underwriter, ud(0.55e18), uint64(expectedMaturity), ONE);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE);
    }

    function test_underwrite_RevertIf_PriceIsZero() public {
        uint256 collateral = _toTokenDecimals(address(base), _size);
        base.mint(underwriter, collateral);
        _setPriceAt(block.timestamp, ZERO);

        vm.startPrank(underwriter);
        base.approve(address(optionReward), collateral);
        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
        optionReward.underwrite(longReceiver, _size);
    }

    function test_underwrite_RevertIf_PriceIsStale() public {
        uint256 collateral = _toTokenDecimals(address(base), _size);
        base.mint(underwriter, collateral);

        vm.prank(underwriter);
        base.approve(address(optionReward), collateral);

        vm.warp(60 days);
        uint256 updatedAt = block.timestamp - 24 hours + 1 seconds;
        _setPriceAt(updatedAt, spot);

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE); // should succeed

        vm.warp(block.timestamp + 1 seconds); // block.timestamp - timestamp = 86400

        vm.expectRevert(
            abi.encodeWithSelector(IOptionReward.OptionReward__PriceIsStale.selector, block.timestamp, updatedAt)
        );

        vm.prank(underwriter);
        optionReward.underwrite(longReceiver, ONE); // should revert
    }
}
