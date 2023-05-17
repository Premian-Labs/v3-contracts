import { ONE_ETHER } from '../../utils/constants';
import { average } from '../../utils/sdk/math';
import { calculateQuoteRFQHash, signQuoteRFQ } from '../../utils/sdk/quoteRFQ';
import { formatTokenId, parseTokenId } from '../../utils/sdk/token';
import { OrderType, TokenType } from '../../utils/sdk/types';
import { increaseTo } from '../../utils/time';
import {
  deploy_CALL,
  deploy_PUT,
  deployAndBuy_CALL,
  deployAndBuy_PUT,
  deployAndDeposit_1000_CS_CALL,
  deployAndDeposit_1000_CS_PUT,
  deployAndDeposit_1000_LC_CALL,
  deployAndDeposit_1000_LC_PUT,
  deployAndMintForLP_CALL,
  deployAndMintForLP_PUT,
  deployAndMintForTraderAndLP_CALL,
  deployAndMintForTraderAndLP_PUT,
  deployAndSell_CALL,
  deployAndSell_PUT,
  depositFnSig,
  protocolFeePercentage,
  runCallAndPutTests,
  strike,
} from './Pool.fixture';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { BigNumber, constants } from 'ethers';
import { parseEther } from 'ethers/lib/utils';

describe('Pool', () => {
  describe('__internal', function () {
    describe('#_getPricing', () => {
      runCallAndPutTests((isCallPool: boolean) => {
        it('should return pool state', async () => {
          const { pool, lp, poolToken, router } = await loadFixture(
            isCallPool ? deploy_CALL : deploy_PUT,
          );

          let isBuy = true;
          let args = await pool._getPricing(isBuy);

          expect(args.liquidityRate).to.eq(0);
          expect(args.marketPrice).to.eq(parseEther('0.001'));
          expect(args.lower).to.eq(parseEther('0.001'));
          expect(args.upper).to.eq(parseEther('1'));
          expect(args.isBuy).to.eq(isBuy);

          args = await pool._getPricing(!isBuy);

          expect(args.liquidityRate).to.eq(0);
          expect(args.marketPrice).to.eq(parseEther('0.001'));
          expect(args.lower).to.eq(parseEther('0.001'));
          expect(args.upper).to.eq(parseEther('1'));
          expect(args.isBuy).to.eq(!isBuy);

          let lower = parseEther('0.25');
          let upper = parseEther('0.75');

          let position = {
            lower: lower,
            upper: upper,
            operator: lp.address,
            owner: lp.address,
            orderType: OrderType.LC,
            isCall: isCallPool,
            strike: strike,
          };

          await poolToken
            .connect(lp)
            .approve(router.address, parseEther('2000'));
          await poolToken.mint(lp.address, parseEther('2000'));

          const nearestBelow = await pool.getNearestTicksBelow(lower, upper);

          await pool
            .connect(lp)
            [depositFnSig](
              position,
              nearestBelow.nearestBelowLower,
              nearestBelow.nearestBelowUpper,
              parseEther('2000'),
              0,
              parseEther('1'),
            );

          args = await pool._getPricing(isBuy);

          expect(args.liquidityRate).to.eq(parseEther('4'));
          expect(args.marketPrice).to.eq(upper);
          expect(args.lower).to.eq(lower);
          expect(args.upper).to.eq(upper);
          expect(args.isBuy).to.eq(isBuy);

          args = await pool._getPricing(!isBuy);

          expect(args.liquidityRate).to.eq(parseEther('4'));
          expect(args.marketPrice).to.eq(upper);
          expect(args.lower).to.eq(lower);
          expect(args.upper).to.eq(upper);
          expect(args.isBuy).to.eq(!isBuy);
        });
      });
    });
  });

  describe('#getQuoteRFQFilledAmount', async () => {
    runCallAndPutTests((isCallPool) => {
      it('should successfully return filled amount of a RFQ quote', async () => {
        const { pool, lp, trader, getQuoteRFQ } = await loadFixture(
          isCallPool
            ? deployAndMintForTraderAndLP_CALL
            : deployAndMintForTraderAndLP_PUT,
        );

        const quoteRFQ = await getQuoteRFQ();

        const sig = await signQuoteRFQ(lp.provider!, pool.address, quoteRFQ);

        await pool
          .connect(trader)
          .fillQuoteRFQ(
            quoteRFQ,
            quoteRFQ.size.div(2),
            sig,
            constants.AddressZero,
          );

        const quoteRFQHash = await calculateQuoteRFQHash(
          lp.provider!,
          quoteRFQ,
          pool.address,
        );
        expect(
          await pool.getQuoteRFQFilledAmount(quoteRFQ.provider, quoteRFQHash),
        ).to.eq(quoteRFQ.size.div(2));
      });
    });
  });

  describe('#getClaimableFees', async () => {
    runCallAndPutTests((isCallPool) => {
      it('should successfully return amount of claimable fees', async () => {
        const { pool, lp, pKey, takerFee } = await loadFixture(
          isCallPool ? deployAndBuy_CALL : deployAndBuy_PUT,
        );

        expect(await pool.connect(lp).getClaimableFees(pKey)).to.eq(
          takerFee
            .mul(parseEther(protocolFeePercentage.toString()))
            .div(ONE_ETHER),
        );
      });
    });
  });

  describe('#claim', () => {
    runCallAndPutTests((isCallPool) => {
      it('should successfully claim fees', async () => {
        const {
          poolToken,
          scaleDecimals,
          pool,
          lp,
          trader,
          pKey,
          feeReceiver,
          initialCollateral,
          tradeSize,
          totalPremium,
          protocolFees,
          contractsToCollateral,
        } = await loadFixture(
          isCallPool ? deployAndBuy_CALL : deployAndBuy_PUT,
        );

        const claimableFees = await pool.getClaimableFees(pKey);

        await pool.connect(lp).claim(pKey);

        const collateral = scaleDecimals(contractsToCollateral(tradeSize));

        expect(await poolToken.balanceOf(pKey.operator)).to.eq(
          initialCollateral.sub(collateral).add(claimableFees),
        );
        expect(await poolToken.balanceOf(pool.address)).to.eq(
          collateral.add(totalPremium).sub(claimableFees).sub(protocolFees),
        );
        expect(await poolToken.balanceOf(feeReceiver.address)).to.eq(
          protocolFees,
        );

        expect(await pool.balanceOf(trader.address, TokenType.LONG)).to.eq(
          ONE_ETHER,
        );
        expect(await pool.balanceOf(pool.address, TokenType.SHORT)).to.eq(
          ONE_ETHER,
        );
      });
    });
  });

  describe('#formatTokenId', () => {
    runCallAndPutTests((isCallPool) => {
      it('should properly format token id', async () => {
        const { pool } = await loadFixture(
          isCallPool ? deploy_CALL : deploy_PUT,
        );

        const operator = '0x1000000000000000000000000000000000000001';
        const tokenId = await pool.formatTokenId(
          operator,
          parseEther('0.001'),
          parseEther('1'),
          OrderType.LC,
        );

        expect(
          formatTokenId({
            version: 1,
            operator,
            lower: parseEther('0.001'),
            upper: parseEther('1'),
            orderType: OrderType.LC,
          }),
        ).to.eq(tokenId);

        console.log(tokenId.toHexString());

        expect(tokenId.mask(10)).to.eq(1);
        expect(tokenId.shr(10).mask(10)).to.eq(1000);
        expect(tokenId.shr(20).mask(160)).to.eq(operator);
        expect(tokenId.shr(180).mask(4)).to.eq(2);
        expect(tokenId.shr(252).mask(4)).to.eq(1);
      });
    });
  });

  describe('#parseTokenId', () => {
    runCallAndPutTests((isCallPool) => {
      it('should properly parse token id', async () => {
        const { pool } = await loadFixture(
          isCallPool ? deploy_CALL : deploy_PUT,
        );

        const tokenId = BigNumber.from(
          '0x10000000000000000021000000000000000000000000000000000000001fa001',
        );

        const r = await pool.parseTokenId(tokenId);

        const parsed = parseTokenId(tokenId);

        expect(r.lower).to.eq(parsed.lower);
        expect(r.upper).to.eq(parsed.upper);
        expect(r.operator).to.eq(parsed.operator);
        expect(r.orderType).to.eq(parsed.orderType);
        expect(r.version).to.eq(parsed.version);

        expect(r.lower).to.eq(parseEther('0.001'));
        expect(r.upper).to.eq(parseEther('1'));
        expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
        expect(r.orderType).to.eq(OrderType.LC);
        expect(r.version).to.eq(1);
      });
    });
  });
});
