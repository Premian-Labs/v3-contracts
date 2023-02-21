import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { ONE_WEEK, now, weekOfMonth } from '../../utils/time';

import moment from 'moment-timezone';
import {BigNumber} from "ethers";
moment.tz.setDefault('UTC');

describe('OptionMath', () => {
  let deployer: SignerWithAddress;
  let instance: OptionMathMock;

  before(async function () {
    [deployer] = await ethers.getSigners();
    instance = await new OptionMathMock__factory(deployer).deploy();
  });

  describe('#helperNormal', function () {
    it('test of the normal CDF approximation helper. should equal the expected value', async () => {
      for (const t of [
        ['-3.0', '0.997937931253017293'],
        ['-2.', '0.972787315787072559'],
        ['-1.', '0.836009939237039072'],
        ['0.', '0.5'],
        ['1.', '0.153320858106603138'],
        ['2.', '0.018287098844188538'],
        ['3.', '0.000638104717830912'],
      ]) {
        expect(
          formatEther(await instance.helperNormal(parseEther(t[0]))),
        ).to.eq(t[1]);
      }
    });
  });

  describe('#normalCDF', function () {
    it('test of the normal CDF approximation. should equal the expected value', async () => {
      for (const t of [
        ['-3.0', '0.001350086732406809'],
        ['-2.', '0.022749891528557989'],
        ['-1.', '0.158655459434782033'],
        ['0.', '0.5'],
        ['1.', '0.841344540565217967'],
        ['2.', '0.97725010847144201'],
        ['3.', '0.99864991326759319'],
      ]) {
        expect(formatEther(await instance.normalCdf(parseEther(t[0])))).to.eq(
          t[1],
        );
      }
    });
  });

  describe('#relu', function () {
    it('test of the relu function. should equal the expected value', async () => {
      for (const t of [
        ['-3.6', '0.'],
        ['-2.2', '0.'],
        ['-1.1', '0.'],
        ['0.', '0.'],
        ['1.1', '1.1'],
        ['2.1', '2.1'],
        ['3.6', '3.6'],
      ]) {
        expect(
          parseFloat(formatEther(await instance.relu(parseEther(t[0])))),
        ).to.eq(parseFloat(t[1]));
      }
    });
  });
  describe('#blackScholesPrice', function () {
    it('test of the Black-Scholes formula', async () => {
      const strike = parseEther('1.');
      const timeToMaturity = parseEther('1.');
      const volAnnualized = parseEther('1.');
      const riskFreeRate = parseEther('0.1');

      it('call', async () => {
        for (const t of [
          ['0.5', '0.10733500381254471'],
          ['0.8', '0.27626266618753637'],
          ['1.0', '0.4139595806172845'],
          ['1.2', '0.5651268636770026'],
          ['2.2', '1.4293073801560254'],
        ]) {
          const result = formatEther(
            await instance.blackScholesPrice(
              parseEther(t[0]),
              strike,
              timeToMaturity,
              volAnnualized,
              riskFreeRate,
              true,
            ),
          );
          expect(parseFloat(result) - parseFloat(t[1])).to.be.closeTo(
            0,
            0.000001,
          );
        }
      });

      it('put', async () => {
        for (const t of [
          ['0.5', '0.5121724218485042'],
          ['0.8', '0.3811000842234958'],
          ['1.0', '0.3187969986532439'],
          ['1.2', '0.26996428171296216'],
          ['2.2', '0.13414479819198477'],
        ]) {
          const result = formatEther(
            await instance.blackScholesPrice(
              parseEther(t[0]),
              strike,
              timeToMaturity,
              volAnnualized,
              riskFreeRate,
              false,
            ),
          );
          expect(parseFloat(result) - parseFloat(t[1])).to.be.closeTo(
            0,
            0.000001,
          );
        }
      });
    });
  });

  describe('#delta', function () {
    it('option delta test', async () => {
      const strike59x18 = parseEther('1.0'); // in ETH
      const timeToMaturity59x18 = parseEther('0.246575'); // 90 days
      const varAnnualized59x18 = parseEther('1.0'); // 100
      const riskFreeRate59x18 = parseEther('0.0');

      for (const t of [
        // calls
        [parseEther('0.3'), true, 0.01476537073867126],
        [parseEther('0.5'), true, 0.12556553467572473],
        [parseEther('0.7'), true, 0.31917577351746684],
        [parseEther('0.9'), true, 0.5143996619519293],
        [parseEther('1.0'), true, 0.5980417972127483],
        [parseEther('1.5'), true, 0.85652221419085],
        [parseEther('2.0'), true, 0.9499294514418426],
        // puts
        [parseEther('0.3'), false, 0.01476537073867126 - 1],
        [parseEther('0.5'), false, 0.12556553467572473 - 1],
        [parseEther('0.7'), false, 0.31917577351746684 - 1],
        [parseEther('0.9'), false, 0.5143996619519293 - 1],
        [parseEther('1.0'), false, 0.5980417972127483 - 1],
        [parseEther('1.5'), false, 0.85652221419085 - 1],
        [parseEther('2.0'), false, 0.9499294514418426 - 1],
      ] as Array<[BigNumber, boolean, number]>) {
        const result = formatEther(
          await instance.optionDelta(
            t[0],
            strike59x18,
            timeToMaturity59x18,
            varAnnualized59x18,
            riskFreeRate59x18,
            t[1],
          ),
        );
        expect(parseFloat(result) - t[2]).to.be.closeTo(
          0,
          0.000001,
        );
      }
    });
  });

  describe('#isFriday', () => {
    describe('should return false if maturity is not Friday', () => {
      for (let c of [
        1674460800, 1674547200, 1674633600, 1674720000, 1674777599, 1674864000,
        1674892800, 1674979200,
      ]) {
        let formattedDayTime = moment.unix(c).format('ddd, h:mm a');

        it(`${formattedDayTime}`, async () => {
          expect(await instance.isFriday(c)).is.false;
        });
      }
    });

    describe('should return true if maturity is Friday', () => {
      for (let c of [1674777600, 1674806400, 1674863999]) {
        let formattedDayTime = moment.unix(c).format('ddd, h:mm a');

        it(`${formattedDayTime}`, async () => {
          expect(await instance.isFriday(c)).is.true;
        });
      }
    });
  });

  describe('#isLastFriday', () => {
    describe('should return false if it is not last week of month', () => {
      for (let c of [
        1675324800, 1675411200, 1675670400, 1676016000, 1676620800, 1676707200,
      ]) {
        let m = moment.unix(c);
        let day = m.format('ddd,');

        let week = weekOfMonth(c);
        week = week === 5 ? 4 : week;

        let monthLength = m.daysInMonth();

        it(`${day} week ${week} ${monthLength}-day month`, async () => {
          expect(await instance.isLastFriday(c)).is.false;
        });
      }
    });

    describe('should return false if last week of month and day is not Friday', () => {
      for (let c of [
        1677139200, 1677312000, 1677571200, 1695625200, 1695798000, 1696057200,
        1703491200, 1703750400, 1704009600,
      ]) {
        let m = moment.unix(c);
        let day = m.format('ddd,');
        let monthLength = m.daysInMonth();

        it(`${day} ${monthLength}-day month`, async () => {
          expect(await instance.isLastFriday(c)).is.false;
        });
      }
    });

    describe('should return true if last week of month and day is Friday', () => {
      for (let c of [1677225600, 1695970800, 1703836800]) {
        let m = moment.unix(c);
        let monthLength = m.daysInMonth();

        it(`${monthLength}-day month`, async () => {
          expect(await instance.isLastFriday(c)).is.true;
        });
      }
    });
  });

  describe('#calculateTimeToMaturity', async () => {
    it('should return the time until maturity', async () => {
      let maturity = (await now()) + ONE_WEEK;
      expect(await instance.calculateTimeToMaturity(maturity)).to.eq(ONE_WEEK);
    });
  });

  describe('#calculateStrikeInterval', () => {
    for (let c of getStrikeIntervals()) {
      it(`should return ${c[1]} when spot price is ${c[0]}`, async () => {
        let spot = parseEther(c[0].toString());
        let interval = await instance.calculateStrikeInterval(spot);

        expect(interval).to.eq(parseEther(c[1].toString()));
      });
    }
  });
});

function getStrikeIntervals() {
  return [
    [1, 0.1],
    [2, 0.1],
    [3, 0.1],
    [4, 0.1],
    [5, 0.5],
    [6, 0.5],
    [7, 0.5],
    [9, 0.5],
    [10, 1],
    [11, 1],
    [33, 1],
    [49, 1],
    [50, 5],
    [51, 5],
    [74, 5],
    [99, 5],
    [100, 10],
    [101, 10],
    [434, 10],
    [499, 10],
    [500, 50],
    [501, 50],
    [871, 50],
    [999, 50],
    [1000, 100],
    [1001, 100],
    [4356, 100],
    [4999, 100],
    [5000, 500],
    [5001, 500],
    [5643, 500],
    [9999, 500],
    [10000, 1000],
    [10001, 1000],
    [35321, 1000],
    [49999, 1000],
    [50000, 5000],
    [50001, 5000],
    [64312, 5000],
    [99999, 5000],
    [100000, 10000],
    [100001, 10000],
    [256110, 10000],
    [499999, 10000],
    [500000, 50000],
    [500001, 50000],
    [862841, 50000],
    [999999, 50000],
    [1000000, 100000],
    [1000001, 100000],
    [4321854, 100000],
    [4999999, 100000],
    [5000000, 500000],
    [5000001, 500000],
    [9418355, 500000],
    [9999999, 500000],
  ];
}
