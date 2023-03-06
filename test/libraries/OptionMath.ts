import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { ONE_WEEK, latest, weekOfMonth } from '../../utils/time';

import moment from 'moment-timezone';
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
        ['-12.0', '1.0000000000000000000'],
        ['-11.0', '1.0000000000000000000'],
        ['-10.0', '1.0000000000000000000'],
        ['-9.0', '1.0000000000000000000'],
        ['-8.0', '1.0000000000000000000'],
        ['-7.0', '0.9999999999998924194'],
        ['-6.0', '0.9999999993614843152'],
        ['-5.0', '0.9999995540985257003'],
        ['-4.0', '0.9999419975714723963'],
        ['-3.0', '0.9979379312530173296'],
        ['-2.0', '0.9727873157870725596'],
        ['-1.0', '0.8360099392370390348'],
        ['0.0', '0.5000000000000000000'],
        ['1.0', '0.1533208581066031195'],
        ['2.0', '0.0182870988441885367'],
        ['3.0', '0.0006381047178309129'],
        ['4.0', '0.0000041315846469876'],
        ['5.0', '0.0000000021829044820'],
        ['6.0', '0.0000000000000231217'],
        ['7.0', '0.0000000000000000000'],
        ['8.0', '0.0000000000000000000'],
        ['9.0', '0.0000000000000000000'],
      ]) {
        expect(
          parseFloat(
            formatEther(await instance.helperNormal(parseEther(t[0]))),
          ),
        ).to.be.closeTo(parseFloat(t[1]), 0.0000000000000001);
      }
    });
  });

  describe('#normalCDF', function () {
    it('test of the normal CDF approximation. should equal the expected value', async () => {
      for (const t of [
        ['-12.0', '0.0000000000000000000'],
        ['-11.0', '0.0000000000000000000'],
        ['-10.0', '0.0000000000000000000'],
        ['-9.0', '0.0000000000000000000'],
        ['-8.0', '0.0000000000000000000'],
        ['-7.0', '0.0000000000000537700'],
        ['-6.0', '0.0000000003192694170'],
        ['-5.0', '0.0000002240421894160'],
        ['-4.0', '0.0000310670065872710'],
        ['-3.0', '0.0013500867324068089'],
        ['-2.0', '0.0227498915285579868'],
        ['-1.0', '0.1586554594347820146'],
        ['0.0', '0.5000000000000000000'],
        ['1.0', '0.8413445405652180131'],
        ['2.0', '0.9772501084714420028'],
        ['3.0', '0.9986499132675932255'],
        ['4.0', '0.9999689329934127180'],
        ['5.0', '0.9999997759578105327'],
        ['6.0', '0.9999999996807306113'],
        ['7.0', '0.9999999999999462652'],
        ['8.0', '1.0000000000000000000'],
        ['9.0', '1.0000000000000000000'],
        ['10.0', '1.0000000000000000000'],
        ['11.0', '1.0000000000000000000'],
        ['12.0', '1.0000000000000000000'],
      ]) {
        expect(
          parseFloat(formatEther(await instance.normalCdf(parseEther(t[0])))),
        ).to.be.closeTo(parseFloat(t[1]), 0.0000000000000001);
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
    const spot = parseEther('1.3');
    const strike = parseEther('0.8');
    const timeToMaturity = parseEther('0.53');
    const volAnnualized = parseEther('0.732');
    const riskFreeRate = parseEther('0.13');
    let cases: [string, string, boolean][];
    it('test of the Black-Scholes formula for varying spot prices', async () => {
      cases = [
        // call
        ['0.001', '0.0', true],
        ['0.5', '0.041651656896334266', true],
        ['0.8', '0.19044728282561157', true],
        ['1.0', '0.3361595989775169', true],
        ['1.2', '0.5037431520530627', true],
        ['2.2', '1.45850009070196', true],
        ['11.000', '10.253264047161903', true],
        // put
        ['0.001', '0.745736013930399', false],
        ['0.5', '0.28838767082673333', false],
        ['0.8', '0.1371832967560106', false],
        ['1.0', '0.08289561290791586', false],
        ['1.2', '0.05047916598346175', false],
        ['2.2', '0.005236104632358806', false],
        ['11.000', '6.109230231221387e-08', false],
      ];
      for (const t of cases) {
        const result = formatEther(
          await instance.blackScholesPrice(
            parseEther(t[0]),
            strike,
            timeToMaturity,
            volAnnualized,
            riskFreeRate,
            t[2],
          ),
        );
        expect(parseFloat(result)).to.be.closeTo(parseFloat(t[1]), 0.00001);
      }
    });
    it('test of the Black-Scholes formula for varying vols', async () => {
      cases = [
        // call
        ['0.001', '0.553263986069601', true],
        ['0.5', '0.5631148171877948', true],
        ['0.8', '0.6042473564031341', true],
        ['1.0', '0.6420186597956653', true],
        ['1.2', '0.6834990708190316', true],
        ['2.2', '0.8941443650200548', true],
        ['11.0', '1.2999387852636883', true],
        // put
        ['0.001', '0.0', false],
        ['0.5', '0.009850831118193633', false],
        ['0.8', '0.05098337033353306', false],
        ['1.0', '0.08875467372606433', false],
        ['1.2', '0.13023508474943063', false],
        ['2.2', '0.34088037895045364', false],
        ['11.0', '0.7466747991940875', false],
      ];
      for (const t of cases) {
        const result = formatEther(
          await instance.blackScholesPrice(
            spot,
            strike,
            timeToMaturity,
            parseEther(t[0]),
            riskFreeRate,
            t[2],
          ),
        );
        expect(parseFloat(result)).to.be.closeTo(parseFloat(t[1]), 0.00001);
      }
    });
  });

  describe('#d1d2', function () {
    const strike = parseEther('0.8');
    const timeToMaturity = parseEther('0.95');
    const volAnnualized = parseEther('1.61');
    const riskFreeRate = parseEther('0.021');
    it('test of the d1d2 function for varying spot prices', async () => {
      let cases: [string, string, string][];
      cases = [
        ['0.5', '0.49781863364936835', '-1.0714152558648748'],
        ['0.8', '0.7973301547720898', '-0.7719037347421535'],
        ['1.0', '0.9395291939371717', '-0.6297046955770715'],
        ['1.2', '1.0557142687129861', '-0.5135196208012571'],
        ['2.2', '1.441976512742106', '-0.12725737677213722'],
      ];
      for (const t of cases) {
        let [d1, d2] = await instance.d1d2(
          parseEther(t[0]),
          strike,
          timeToMaturity,
          volAnnualized,
          riskFreeRate,
        );
        expect(parseFloat(formatEther(d1)) - parseFloat(t[1])).to.be.closeTo(
          0,
          0.00000000000001,
        );
        expect(parseFloat(formatEther(d2)) - parseFloat(t[2])).to.be.closeTo(
          0,
          0.00000000000001,
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
      let maturity = (await latest()) + ONE_WEEK;
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
