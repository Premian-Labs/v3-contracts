// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;
//
//import {Test} from "forge-std/Test.sol";
//import {UD60x18, ud} from "@prb/math/UD60x18.sol";
//import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
//import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
//import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
//import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
//
//import {ZERO, ONE} from "contracts/libraries/Constants.sol";
//import {OptionMath} from "contracts/libraries/OptionMath.sol";
//import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
//import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
//
//import {IOptionReward} from "contracts/mining/optionReward/OptionReward.sol";
//import {IOptionRewardFactory} from "contracts/mining/optionReward/IOptionRewardFactory.sol";
//import {OptionRewardMock} from "contracts/test/mining/OptionRewardMock.sol";
//import {OptionRewardStorage} from "contracts/mining/optionReward/OptionRewardStorage.sol";
//import {OptionRewardFactory} from "contracts/mining/optionReward/OptionRewardFactory.sol";
//
//import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
//import {PriceRepository} from "contracts/mining/PriceRepository.sol";
//
//import {PaymentSplitter} from "contracts/mining/PaymentSplitter.sol";
//
//import {IVxPremia} from "contracts/staking/IVxPremia.sol";
//import {VxPremia} from "contracts/staking/VxPremia.sol";
//import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";
//
//import {Assertions} from "../Assertions.sol";
//
//contract OptionRewardTest is Assertions, Test {
//    using SafeCast for int256;
//    using SafeCast for uint256;
//
//    PaymentSplitter internal paymentSplitter;
//    PriceRepository internal priceRepository;
//    OptionRewardMock internal optionReward;
//
//    UD60x18 internal fee;
//    UD60x18 internal _size;
//    uint256 internal size;
//
//    Users internal users;
//
//    address internal vxPremia;
//    address internal base;
//    address internal quote;
//
//    DataInternal internal data;
//
//    struct DataInternal {
//        UD60x18 discount;
//        UD60x18 spot;
//        UD60x18 settlementITM;
//        UD60x18 penalty;
//        uint256 expiryDuration;
//        uint256 exerciseDuration;
//        uint256 lockupDuration;
//    }
//
//    struct Users {
//        address underwriter;
//        address longReceiver;
//        address keeper;
//        address treasury;
//    }
//
//    function setUp() public {
//        string memory ETH_RPC_URL = string.concat(
//            "https://eth-mainnet.alchemyapi.io/v2/",
//            vm.envString("API_KEY_ALCHEMY")
//        );
//
//        uint256 fork = vm.createFork(ETH_RPC_URL, 17101000); // Apr-22-2023 09:30:23 AM +UTC
//        vm.selectFork(fork);
//
//        fee = ud(0.01e18);
//
//        base = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA (18 decimals)
//        quote = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC (6 decimals)
//
//        users = Users({underwriter: vm.addr(1), longReceiver: vm.addr(2), keeper: vm.addr(3), treasury: vm.addr(4)});
//
//        VxPremia vxPremiaImpl = new VxPremia(address(0), address(0), address(base), address(quote), address(0));
//        VxPremiaProxy vxPremiaProxy = new VxPremiaProxy(address(vxPremiaImpl));
//        vxPremia = address(vxPremiaProxy);
//
//        paymentSplitter = new PaymentSplitter(quote, vxPremia);
//
//        PriceRepository implementation = new PriceRepository();
//        PriceRepositoryProxy proxy = new PriceRepositoryProxy(address(implementation), users.keeper);
//        priceRepository = PriceRepository(address(proxy));
//
//        OptionRewardMock optionRewardImplementation = new OptionRewardMock(users.treasury, fee);
//        ProxyUpgradeableOwnable optionRewardProxy = new ProxyUpgradeableOwnable(address(optionRewardImplementation));
//        OptionRewardFactory optionRewardFactory = new OptionRewardFactory(address(optionRewardProxy));
//
//        data = DataInternal(ud(0.55e18), ud(1e18), ud(2e18), ud(0.80e18), 30 days, 30 days, 365 days);
//        size = 1000000e18;
//        _size = ud(size);
//
//        IOptionRewardFactory.OptionRewardArgs memory args = IOptionRewardFactory.OptionRewardArgs(
//            base,
//            quote,
//            users.underwriter,
//            address(priceRepository),
//            address(paymentSplitter),
//            data.discount,
//            data.penalty,
//            data.expiryDuration,
//            data.exerciseDuration,
//            data.lockupDuration
//        );
//
//        optionReward = OptionRewardMock(optionRewardFactory.deployProxy(args));
//
//        assertTrue(optionRewardFactory.isProxyDeployed(address(optionReward)));
//        (address _optionReward, ) = optionRewardFactory.getProxyAddress(args);
//        assertEq(address(optionReward), _optionReward);
//    }
//
//    function _getMaturity(uint256 timestamp, uint256 expiryDuration) internal pure returns (uint256 maturity) {
//        maturity = timestamp - (timestamp % 24 hours) + 8 hours + expiryDuration;
//    }
//
//    function _setPriceAt(uint256 timestamp, UD60x18 price) internal {
//        vm.prank(users.keeper);
//        priceRepository.setPriceAt(base, quote, timestamp, price);
//    }
//
//    function _toTokenDecimals(address token, UD60x18 amount) internal view returns (uint256) {
//        uint8 decimals = IERC20Metadata(token).decimals();
//        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
//    }
//
//    function _test_writeFrom_Success()
//        internal
//        returns (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId)
//    {
//        maturity = uint64(_getMaturity(block.timestamp, data.expiryDuration));
//        _setPriceAt(block.timestamp, data.spot);
//
//        collateral = _toTokenDecimals(base, _size);
//        deal(base, users.underwriter, collateral);
//
//        vm.startPrank(users.underwriter);
//        IERC20(base).approve(address(optionReward), collateral);
//        optionReward.writeFrom(users.longReceiver, _size);
//        vm.stopPrank();
//
//        UD60x18 strike = data.discount * data.spot;
//        longTokenId = optionReward.formatTokenId(IOptionReward.TokenType.LONG, maturity, strike);
//        shortTokenId = optionReward.formatTokenId(IOptionReward.TokenType.SHORT, maturity, strike);
//
//        assertEq(optionReward.balanceOf(users.longReceiver, longTokenId), size);
//        assertEq(optionReward.balanceOf(users.longReceiver, shortTokenId), 0);
//        assertEq(optionReward.balanceOf(users.underwriter, shortTokenId), size);
//        assertEq(optionReward.balanceOf(users.underwriter, longTokenId), 0);
//
//        assertEq(IERC20(base).balanceOf(users.underwriter), 0);
//        assertEq(IERC20(base).balanceOf(address(optionReward)), collateral);
//    }
//
//    function test_writeFrom_Success() public {
//        _test_writeFrom_Success();
//    }
//
//    event WriteFrom(
//        address indexed underwriter,
//        address indexed longReceiver,
//        UD60x18 contractSize,
//        UD60x18 strike,
//        uint256 maturity
//    );
//
//    function test_writeFrom_CorrectMaturity() public {
//        _setPriceAt(block.timestamp, ONE);
//
//        uint256 collateral = _toTokenDecimals(base, ud(100e18));
//        deal(base, users.underwriter, collateral);
//
//        vm.prank(users.underwriter);
//        IERC20(base).approve(address(optionReward), collateral);
//
//        // block.timestamp = Apr-22-2023 09:30:23 AM +UTC
//        uint256 expiryDuration = 30 days;
//        uint256 timestamp8AMUTC = 1682150400; // Apr-22-2023 08:00:00 AM +UTC
//        uint256 expectedMaturity = timestamp8AMUTC + expiryDuration; // May-22-2023 08:00:00 AM +UTC
//
//        vm.expectEmit();
//        emit WriteFrom(users.underwriter, users.longReceiver, ONE, ud(0.55e18), expectedMaturity);
//
//        vm.prank(users.underwriter);
//        optionReward.writeFrom(users.longReceiver, ONE);
//
//        vm.warp(1682207999); // Apr-22-2023 23:59:59 PM +UTC
//
//        expectedMaturity = timestamp8AMUTC + expiryDuration; // May-22-2023 08:00:00 AM +UTC
//        vm.expectEmit();
//        emit WriteFrom(users.underwriter, users.longReceiver, ONE, ud(0.55e18), expectedMaturity);
//
//        vm.prank(users.underwriter);
//        optionReward.writeFrom(users.longReceiver, ONE);
//
//        vm.warp(1682208000); // Apr-23-2023 00:00:00 AM +UTC
//
//        timestamp8AMUTC = 1682236800; // Apr-23-2023 08:00:00 AM +UTC
//        expectedMaturity = timestamp8AMUTC + expiryDuration; // May-23-2023 08:00:00 AM +UTC
//        vm.expectEmit();
//        emit WriteFrom(users.underwriter, users.longReceiver, ONE, ud(0.55e18), expectedMaturity);
//
//        vm.prank(users.underwriter);
//        optionReward.writeFrom(users.longReceiver, ONE);
//    }
//
//    function test_writeFrom_RevertIf_PriceIsZero() public {
//        uint256 collateral = _toTokenDecimals(base, _size);
//        deal(base, users.underwriter, collateral);
//        _setPriceAt(block.timestamp, ZERO);
//
//        vm.startPrank(users.underwriter);
//        IERC20(base).approve(address(optionReward), collateral);
//        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
//        optionReward.writeFrom(users.longReceiver, _size);
//        vm.stopPrank();
//    }
//
//    function test_writeFrom_RevertIf_PriceIsStale() public {
//        uint256 collateral = _toTokenDecimals(base, _size);
//        deal(base, users.underwriter, collateral);
//
//        vm.prank(users.underwriter);
//        IERC20(base).approve(address(optionReward), collateral);
//
//        uint256 updatedAt = block.timestamp - 24 hours + 1 seconds; // block.timestamp - timestamp = 86399
//        _setPriceAt(updatedAt, data.spot);
//
//        vm.prank(users.underwriter);
//        optionReward.writeFrom(users.longReceiver, ONE); // should succeed
//
//        vm.warp(block.timestamp + 1 seconds); // block.timestamp - timestamp = 86400
//
//        vm.expectRevert(
//            abi.encodeWithSelector(IOptionReward.OptionReward__PriceIsStale.selector, block.timestamp, updatedAt)
//        );
//
//        vm.prank(users.underwriter);
//        optionReward.writeFrom(users.longReceiver, ONE); // should revert
//    }
//
//    function test_writeFrom_RevertIf_UnderwriterNotAuthorized() public {
//        vm.expectRevert(
//            abi.encodeWithSelector(IOptionReward.OptionReward__UnderwriterNotAuthorized.selector, users.longReceiver)
//        );
//
//        vm.prank(users.longReceiver);
//        optionReward.writeFrom(users.longReceiver, _size);
//    }
//
//    function test_exercise_PhysicallySettled_Success() public {
//        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success();
//
//        vm.warp(maturity);
//        _setPriceAt(maturity, data.settlementITM);
//
//        UD60x18 _strike = data.discount * data.spot;
//
//        vm.startPrank(users.longReceiver);
//        UD60x18 _exerciseCost = _size * _strike;
//        uint256 exerciseCost = _toTokenDecimals(quote, _exerciseCost);
//        deal(quote, users.longReceiver, exerciseCost);
//
//        assertEq(IERC20(quote).balanceOf(users.longReceiver), exerciseCost);
//
//        IERC20(quote).approve(address(optionReward), exerciseCost);
//        optionReward.exercise(longTokenId, _size);
//        vm.stopPrank();
//
//        assertEq(optionReward.balanceOf(users.longReceiver, longTokenId), 0);
//        assertEq(optionReward.balanceOf(users.longReceiver, shortTokenId), 0);
//        assertEq(optionReward.balanceOf(users.underwriter, shortTokenId), size);
//        assertEq(optionReward.balanceOf(users.underwriter, longTokenId), 0);
//
//        assertEq(IERC20(quote).balanceOf(users.longReceiver), 0);
//        assertEq(IERC20(quote).balanceOf(users.underwriter), 0);
//
//        {
//            uint256 feeAmount = _toTokenDecimals(quote, fee * _exerciseCost);
//            assertEq(IERC20(quote).balanceOf(users.treasury), feeAmount);
//            assertEq(IERC20(quote).balanceOf(vxPremia), exerciseCost - feeAmount);
//            assertEq(IERC20(quote).balanceOf(address(paymentSplitter)), 0);
//        }
//
//        assertEq(IERC20(base).balanceOf(users.longReceiver), collateral);
//        assertEq(IERC20(base).balanceOf(users.underwriter), 0);
//        assertEq(IERC20(base).balanceOf(address(optionReward)), 0);
//    }
//
//    function test_exercise_CashSettled_Success() public {
//        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success();
//
//        vm.warp(maturity);
//        _setPriceAt(maturity, data.settlementITM);
//
//        {
//            uint256 lockupStart = maturity + data.exerciseDuration;
//            uint256 lockupEnd = lockupStart + data.lockupDuration;
//            vm.warp(lockupEnd);
//        }
//
//        uint256 exerciseValue;
//        {
//            UD60x18 intrinsicValue = data.settlementITM - data.discount * data.spot;
//            UD60x18 _exerciseValue = (_size * intrinsicValue) / data.settlementITM;
//            _exerciseValue = _exerciseValue * (ONE - data.penalty);
//            exerciseValue = _toTokenDecimals(base, _exerciseValue);
//        }
//
//        vm.prank(users.longReceiver);
//        optionReward.exercise(longTokenId, _size);
//
//        assertEq(optionReward.balanceOf(users.longReceiver, longTokenId), 0);
//        assertEq(optionReward.balanceOf(users.longReceiver, shortTokenId), 0);
//        assertEq(optionReward.balanceOf(users.underwriter, shortTokenId), size);
//        assertEq(optionReward.balanceOf(users.underwriter, longTokenId), 0);
//
//        assertEq(IERC20(quote).balanceOf(users.longReceiver), 0);
//        assertEq(IERC20(quote).balanceOf(users.underwriter), 0);
//
//        assertEq(IERC20(quote).balanceOf(vxPremia), 0);
//        assertEq(IERC20(quote).balanceOf(users.treasury), 0);
//        assertEq(IERC20(quote).balanceOf(address(paymentSplitter)), 0);
//
//        assertEq(IERC20(base).balanceOf(users.longReceiver), exerciseValue);
//        assertApproxEqAbs(IERC20(base).balanceOf(users.underwriter), collateral - exerciseValue, 1); // handles rounding error of 1 wei
//        assertApproxEqAbs(IERC20(base).balanceOf(address(optionReward)), 0, 1); // handles rounding error of 1 wei
//    }
//
//    function test_exercise_RevertIf_PriceIsZero() public {
//        (uint64 maturity, , uint256 longTokenId, ) = _test_writeFrom_Success();
//        vm.warp(maturity);
//        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
//        vm.prank(users.longReceiver);
//        optionReward.exercise(longTokenId, _size);
//    }
//
//    function test_exercise_RevertIf_TokenTypeNotLong() public {
//        uint64 maturity = uint64(_getMaturity(block.timestamp, data.expiryDuration));
//
//        UD60x18 strike = data.discount * data.spot;
//        uint256 shortTokenId = optionReward.formatTokenId(IOptionReward.TokenType.SHORT, maturity, strike);
//
//        vm.expectRevert(IOptionReward.OptionReward__TokenTypeNotLong.selector);
//        vm.prank(users.longReceiver);
//        optionReward.exercise(shortTokenId, ud(1000000e18));
//    }
//
//    function test_exercise_RevertIf_OptionNotExpired() public {
//        uint64 maturity = uint64(_getMaturity(block.timestamp, data.expiryDuration));
//
//        UD60x18 strike = data.discount * data.spot;
//        uint256 longTokenId = optionReward.formatTokenId(IOptionReward.TokenType.LONG, maturity, strike);
//
//        vm.expectRevert(abi.encodeWithSelector(IOptionReward.OptionReward__OptionNotExpired.selector, maturity));
//        vm.warp(maturity - 1);
//        vm.prank(users.longReceiver);
//        optionReward.exercise(longTokenId, ud(1000000e18));
//    }
//
//    function test_exercise_RevertIf_OptionOutTheMoney() public {
//        (uint64 maturity, , uint256 longTokenId, ) = _test_writeFrom_Success();
//
//        UD60x18 _strike = data.discount * data.spot;
//        UD60x18 settlementOTM = _strike.sub(ud(1));
//
//        vm.warp(maturity);
//        _setPriceAt(maturity, settlementOTM);
//
//        vm.expectRevert(
//            abi.encodeWithSelector(IOptionReward.OptionReward__OptionOutTheMoney.selector, settlementOTM, _strike)
//        );
//
//        vm.prank(users.longReceiver);
//        optionReward.exercise(longTokenId, _size);
//    }
//
//    function test_exercise_RevertIf_LockupNotExpired() public {
//        (uint64 maturity, , uint256 longTokenId, ) = _test_writeFrom_Success();
//        vm.warp(maturity);
//        _setPriceAt(maturity, data.settlementITM);
//
//        uint256 lockupStart = maturity + data.exerciseDuration;
//        uint256 lockupEnd = lockupStart + data.lockupDuration;
//
//        vm.warp(lockupStart);
//
//        vm.expectRevert(
//            abi.encodeWithSelector(IOptionReward.OptionReward__LockupNotExpired.selector, lockupStart, lockupEnd)
//        );
//
//        vm.prank(users.longReceiver);
//        optionReward.exercise(longTokenId, _size);
//    }
//
//    function test_settle_Success() public {
//        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success();
//
//        UD60x18 _strike = data.discount * data.spot;
//        UD60x18 settlementOTM = _strike.sub(ud(1));
//
//        vm.warp(maturity);
//        _setPriceAt(maturity, settlementOTM);
//
//        vm.prank(users.underwriter);
//        optionReward.settle(shortTokenId, _size);
//
//        assertEq(optionReward.balanceOf(users.longReceiver, longTokenId), size);
//        assertEq(optionReward.balanceOf(users.longReceiver, shortTokenId), 0);
//        assertEq(optionReward.balanceOf(users.underwriter, shortTokenId), 0);
//        assertEq(optionReward.balanceOf(users.underwriter, longTokenId), 0);
//
//        assertEq(IERC20(quote).balanceOf(users.longReceiver), 0);
//        assertEq(IERC20(quote).balanceOf(users.underwriter), 0);
//
//        assertEq(IERC20(quote).balanceOf(vxPremia), 0);
//        assertEq(IERC20(quote).balanceOf(users.treasury), 0);
//
//        assertEq(IERC20(base).balanceOf(users.longReceiver), 0);
//        assertEq(IERC20(base).balanceOf(users.underwriter), collateral);
//        assertEq(IERC20(base).balanceOf(address(optionReward)), 0);
//    }
//
//    function test_settle_RevertIf_PriceIsZero() public {
//        (uint64 maturity, , , uint256 shortTokenId) = _test_writeFrom_Success();
//        vm.warp(maturity);
//        vm.expectRevert(IOptionReward.OptionReward__PriceIsZero.selector);
//        vm.prank(users.underwriter);
//        optionReward.settle(shortTokenId, _size);
//    }
//
//    function test_settle_RevertIf_TokenTypeNotShort() public {
//        uint64 maturity = uint64(_getMaturity(block.timestamp, data.expiryDuration));
//
//        UD60x18 strike = data.discount * data.spot;
//        uint256 longTokenId = optionReward.formatTokenId(IOptionReward.TokenType.LONG, maturity, strike);
//
//        vm.expectRevert(IOptionReward.OptionReward__TokenTypeNotShort.selector);
//
//        vm.prank(users.underwriter);
//        optionReward.settle(longTokenId, ud(1000000e18));
//    }
//
//    function test_settle_RevertIf_OptionNotExpired() public {
//        (uint64 maturity, , , uint256 shortTokenId) = _test_writeFrom_Success();
//        vm.expectRevert(abi.encodeWithSelector(IOptionReward.OptionReward__OptionNotExpired.selector, maturity));
//        vm.prank(users.underwriter);
//        optionReward.settle(shortTokenId, _size);
//    }
//
//    function test_settle_RevertIf_OptionInTheMoney() public {
//        (uint64 maturity, , , uint256 shortTokenId) = _test_writeFrom_Success();
//        vm.warp(maturity);
//        _setPriceAt(maturity, data.settlementITM);
//
//        vm.expectRevert(
//            abi.encodeWithSelector(
//                IOptionReward.OptionReward__OptionInTheMoney.selector,
//                data.settlementITM,
//                data.discount * data.spot
//            )
//        );
//
//        vm.prank(users.underwriter);
//        optionReward.settle(shortTokenId, _size);
//    }
//}
