// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {ChainlinkOraclePriceStub} from "contracts/test/adapter/ChainlinkOraclePriceStub.sol";

import {ChainlinkAdapter_PathCases_Shared_Test} from "../shared/pathCases.t.sol";

contract ChainlinkAdapter_GetPriceAt_Fork_Concrete_Test is ChainlinkAdapter_PathCases_Shared_Test {
    function isForkTest() internal virtual override returns (bool) {
        return true;
    }

    function test_getPriceAt_ReturnPriceForPairFromTarget() public givenPaths {
        // Expected price values provided by DeFiLlama API (https://coins.llama.fi)
        uint80[39] memory expected = [
            1552329999999999927240, // WETH CHAINLINK_USD
            644192922896549, // CHAINLINK_USD WETH
            1553210000000000036380, // CHAINLINK_ETH CHAINLINK_USD
            1000999999999999890, // DAI CHAINLINK_USD
            79620000000000004547, // AAVE CHAINLINK_USD
            45583006655119, // CHAINLINK_USD WBTC
            21938000000000000000000, // WBTC CHAINLINK_USD
            282841277305728, // BNT WETH
            6609419388918594, // AXS WETH
            1560637272199920062121, // WETH CRV
            12492803315749812, // CRV AAVE
            12572218035669427, // DAI AAVE
            79540459540459551135, // AAVE DAI
            992691616766467111, // CRV USDC
            20242424242424242, // USDC COMP
            45628589661774, // DAI WBTC
            21894211576846308162203, // WBTC USDC
            413255360623781709, // BOND AXS
            28558726415094340, // ALPHA BOND
            7930014880856519, // FXS WETH
            1232007936507936392445, // WETH MATIC
            97660818713450295, // USDC AXS
            120968031968031978, // ALPHA DAI
            8266646846534365878, // DAI ALPHA
            1199805068226120985, // FXS AXS
            96102380952380953, // ALPHA MATIC
            70759868720940824, // WETH WBTC
            1732435753354485541422, // WETH IMX
            577221982439301, // IMX WETH
            11450394458276926812, // AXS IMX
            2903301886792452713, // FXS BOND
            344435418359057666, // BOND FXS
            21938000000000000000000, // WBTC CHAINLINK_USD
            999225688909132326, // WBTC CHAINLINK_BTC
            14132304342504493633, // WBTC WETH
            70759868720940824, // WETH WBTC
            45628589661774, // DAI WBTC
            21894211576846308162203, // WBTC USDC
            49965494701215997338295 // WBTC BNT
        ];

        UD60x18 price = adapter.getPriceAt(p.tokenIn, p.tokenOut, target);

        assertApproxEqAbs(
            price.unwrap(),
            expected[caseId],
            (expected[caseId] * 3) / 100 // 3% tolerance
        );
    }

    function test_getPriceAt_Return1e18ForPairWithSameFeed() public {
        // tokenIn > tokenOut, tokenIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        address testWETH = address(new ERC20Mock("testWETH", 18));

        IFeedRegistry.FeedMappingArgs[] memory feedMapping = new IFeedRegistry.FeedMappingArgs[](1);

        feedMapping[0] = IFeedRegistry.FeedMappingArgs(
            testWETH,
            CHAINLINK_USD,
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 // Same feed as WETH/USD
        );

        adapter.batchRegisterFeedMappings(feedMapping);
        assertEq(adapter.getPriceAt(WETH, testWETH, target), ud(1e18));
        assertEq(adapter.getPriceAt(testWETH, WETH, target), ud(1e18));
    }

    function test_getPriceAt_CatchRevert() public {
        adapter.upsertPair(stubCoin, CHAINLINK_USD);

        int256[] memory prices = new int256[](3);
        uint256[] memory timestamps = new uint256[](3);

        prices[0] = 100000000000;
        prices[1] = 100000000000;
        prices[2] = 100000000000;

        timestamps[0] = target + 3;
        timestamps[1] = target + 2;
        timestamps[2] = target + 1;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.GetRoundDataRevertWithReason, prices, timestamps);

        vm.expectRevert("reverted with reason");
        adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);

        //

        stub.setup(ChainlinkOraclePriceStub.FailureMode.GetRoundDataRevert, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__GetRoundDataCallReverted.selector, "")
        );
        adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
    }

    function test_getPriceAt_RevertIf_TargetIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidTarget.selector, 0, block.timestamp)
        );
        adapter.getPriceAt(WETH, DAI, 0);
    }

    function test_getPriceAt_RevertIf_TargetGtBlockTimestamp() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__InvalidTarget.selector,
                block.timestamp + 1,
                block.timestamp
            )
        );
        adapter.getPriceAt(WETH, DAI, block.timestamp + 1);
    }

    function test_getPriceAt_ReturnsLeftOfTarget() public {
        {
            int256[] memory prices = new int256[](4);
            prices[0] = 0;
            prices[1] = 5000000000;
            prices[2] = 10000000000;
            prices[3] = 50000000000;

            // left and right of target are equidistant from target but the left side is returned
            uint256[] memory timestamps = new uint256[](4);
            timestamps[0] = 0;
            timestamps[1] = target - 10;
            timestamps[2] = target + 10;
            timestamps[3] = target + 50;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(1);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }

        {
            int256[] memory prices = new int256[](4);
            prices[0] = 0;
            prices[1] = 5000000000;
            prices[2] = 10000000000;
            prices[3] = 50000000000;

            // left of target is further from target than right, but the left side is returned
            uint256[] memory timestamps = new uint256[](4);
            timestamps[0] = 0;
            timestamps[1] = target - 20;
            timestamps[2] = target + 10;
            timestamps[3] = target + 50;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(1);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }
    }

    function test_getPriceAt_UpdatedAtEqTarget() public {
        {
            // target == updatedAt at AggregatorRoundId = 1
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 100000000000;
            prices[2] = 200000000000;
            prices[3] = 300000000000;
            prices[4] = 400000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target;
            timestamps[2] = target + 200;
            timestamps[3] = target + 300;
            timestamps[4] = target + 400;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(1);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }

        {
            // target == updatedAt at AggregatorRoundId = 2
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 50000000000;
            prices[2] = 100000000000;
            prices[3] = 200000000000;
            prices[4] = 300000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target - 100;
            timestamps[2] = target;
            timestamps[3] = target + 100;
            timestamps[4] = target + 200;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(2);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }
    }

    function test_getPriceAt_HandleAggregatorRoundIdEq1() public {
        {
            // closest round update is left of target
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 50000000000;
            prices[2] = 100000000000;
            prices[3] = 200000000000;
            prices[4] = 300000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target - 50;
            timestamps[2] = target + 100;
            timestamps[3] = target + 200;
            timestamps[4] = target + 300;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(1);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }

        {
            // closest round update is right of target we always return price left of target unless the left price is stale
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 50000000000;
            prices[2] = 100000000000;
            prices[3] = 200000000000;
            prices[4] = 300000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target - 100;
            timestamps[2] = target + 50;
            timestamps[3] = target + 300;
            timestamps[4] = target + 500;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
            int256 freshPrice = stub.price(1);
            assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
        }
    }

    function test_getPriceAt_ReturnsClosestPriceLeftOfTarget() public {
        // feed only has prices left of target, adapter returns price closest to target
        int256[] memory prices = new int256[](3);
        prices[0] = 0;
        prices[1] = 50000000000;
        prices[2] = 100000000000;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = 0;
        timestamps[1] = target - 100;
        timestamps[2] = target - 50;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
        int256 freshPrice = stub.price(2);
        assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
    }

    function test_getPriceAt_ChecksLeftAndRightOfTarget() public {
        int256[] memory prices = new int256[](7);
        prices[0] = 0;
        prices[1] = 50000000000;
        prices[2] = 100000000000;
        prices[3] = 200000000000;
        prices[4] = 300000000000;
        prices[5] = 400000000000;
        prices[6] = 500000000000;

        uint256[] memory timestamps = new uint256[](7);
        timestamps[0] = 0;
        timestamps[1] = target - 500;
        timestamps[2] = target - 100;
        timestamps[3] = target - 50; // second improvement
        timestamps[4] = target - 10; // first improvement (closest)
        timestamps[5] = target + 100;
        timestamps[6] = target + 500;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);
        int256 freshPrice = stub.price(4);
        assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), ud(uint256(freshPrice) * 1e10));
    }

    function test_getPriceAt_ReturnPriceOverrideAtTarget() public {
        UD60x18 priceOverride = ud(9e18);

        address[] memory relayers = new address[](1);
        relayers[0] = users.relayer;

        adapter.addWhitelistedRelayers(relayers);

        changePrank(users.relayer);

        adapter.setTokenPriceAt(stubCoin, CHAINLINK_USD, target, priceOverride);
        adapter.setTokenPriceAt(stubCoin, CHAINLINK_ETH, target, priceOverride);

        int256[] memory prices = new int256[](7);
        prices[0] = 0;
        prices[1] = 50000000000;
        prices[2] = 100000000000;
        prices[3] = 200000000000;
        prices[4] = 300000000000;
        prices[5] = 400000000000;
        prices[6] = 500000000000;

        uint256[] memory timestamps = new uint256[](7);
        timestamps[0] = 0;
        timestamps[1] = target - 500;
        timestamps[2] = target - 100;
        timestamps[3] = target - 50;
        timestamps[4] = target;
        timestamps[5] = target + 100;
        timestamps[6] = target + 500;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

        // decimals == 8, internal logic should scale the price override (18 decimals) to feed decimals (8 decimals)
        assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_USD, target), priceOverride);

        // decimals == 18, no scaling necessary
        assertEq(adapter.getPriceAt(stubCoin, CHAINLINK_ETH, target), priceOverride);
    }

    function test_getPriceAt_RevertIf_PriceAtOrLeftOfTargetNotFound() public {
        // price at or to left of target is not found
        int256[] memory prices = new int256[](4);
        prices[0] = 0;
        prices[1] = 100000000000;
        prices[2] = 200000000000;
        prices[3] = 300000000000;

        uint256[] memory timestamps = new uint256[](4);
        timestamps[0] = 0;
        timestamps[1] = target + 50;
        timestamps[2] = target + 100;
        timestamps[3] = target + 200;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

        vm.expectRevert(
            abi.encodeWithSelector(
                IChainlinkAdapter.ChainlinkAdapter__PriceAtOrLeftOfTargetNotFound.selector,
                stubCoin,
                CHAINLINK_USD,
                target
            )
        );

        adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
    }

    function test_getPriceAt_RevertIf_InvalidPrice() public {
        int256[] memory prices = new int256[](4);
        prices[0] = 0;
        prices[1] = 0;
        prices[2] = 200000000000;
        prices[3] = 300000000000;

        uint256[] memory timestamps = new uint256[](4);
        timestamps[0] = 0;
        timestamps[1] = target;
        timestamps[2] = target + 100;
        timestamps[3] = target + 200;

        stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__InvalidPrice.selector, prices[1]));
        adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
    }

    function test_getPriceAt_RevertIf_PriceLeftOfTargetStale() public {
        {
            // left is stale and right does not exist
            int256[] memory prices = new int256[](4);
            prices[0] = 0;
            prices[1] = 100000000000;
            prices[2] = 200000000000;
            prices[3] = 300000000000;

            uint256[] memory timestamps = new uint256[](4);
            timestamps[0] = 0;
            timestamps[1] = target - 110000;
            timestamps[2] = target - 100000;
            timestamps[3] = target - 90001;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IChainlinkAdapter.ChainlinkAdapter__PriceLeftOfTargetStale.selector,
                    timestamps[3],
                    target
                )
            );

            adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
        }

        {
            // left is stale but right is closer to target
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 100000000000;
            prices[2] = 200000000000;
            prices[3] = 300000000000;
            prices[4] = 400000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target - 110000;
            timestamps[2] = target - 100000;
            timestamps[3] = target - 90001;
            timestamps[4] = target + 10;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IChainlinkAdapter.ChainlinkAdapter__PriceLeftOfTargetStale.selector,
                    timestamps[3],
                    target
                )
            );

            adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
        }

        {
            // left and right are both stale but right is closer to target
            int256[] memory prices = new int256[](5);
            prices[0] = 0;
            prices[1] = 100000000000;
            prices[2] = 200000000000;
            prices[3] = 300000000000;
            prices[4] = 400000000000;

            uint256[] memory timestamps = new uint256[](5);
            timestamps[0] = 0;
            timestamps[1] = target - 110000;
            timestamps[2] = target - 100000;
            timestamps[3] = target - 90002;
            timestamps[4] = target + 90001;

            stub.setup(ChainlinkOraclePriceStub.FailureMode.None, prices, timestamps);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IChainlinkAdapter.ChainlinkAdapter__PriceLeftOfTargetStale.selector,
                    timestamps[3],
                    target
                )
            );

            adapter.getPriceAt(stubCoin, CHAINLINK_USD, target);
        }
    }

    function test_getPriceAt_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairNotSupported.selector, WETH, address(1))
        );
        adapter.getPriceAt(WETH, address(1), target);
    }

    function test_getPriceAt_RevertIf_TokensAreSame() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, CRV, CRV));
        adapter.getPriceAt(CRV, CRV, target);
    }

    function test_getPriceAt_RevertIf_ZeroAddress() public {
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.getPriceAt(address(0), DAI, target);

        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.getPriceAt(CRV, address(0), target);
    }
}
