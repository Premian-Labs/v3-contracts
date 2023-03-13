import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  ProxyUpgradeableOwnable__factory,
  VolatilityOracleMock__factory,
} from '../../typechain';

import { BigNumber } from 'ethers';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('VolatilityOracle', () => {
  const paramsFormatted =
    '0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8';
  const params = [
    0.839159148341129, -0.05957422656606383, 0.02004706385514592,
    0.14895038484273854, 0.034026549310791646,
  ].map((el) => Math.floor(el * 10 ** 12).toString());

  beforeEach(async () => {});

  async function deploy() {
    const [owner, relayer, user] = await ethers.getSigners();

    const impl = await new VolatilityOracleMock__factory(owner).deploy();
    const proxy = await new ProxyUpgradeableOwnable__factory(owner).deploy(
      impl.address,
    );
    const oracle = VolatilityOracleMock__factory.connect(proxy.address, owner);

    await oracle.connect(owner).addWhitelistedRelayers([relayer.address]);

    return { owner, relayer, user, oracle, proxy };
  }

  async function deployAndUpdateParams() {
    const f = await deploy();

    const token = '0x0000000000000000000000000000000000000001';
    const tau = [
      0.0027397260273972603, 0.03561643835616438, 0.09315068493150686,
      0.16986301369863013, 0.4191780821917808,
    ].map((el) => Math.floor(el * 10 ** 12));

    const theta = [
      0.0017692409901229372, 0.01916765969267577, 0.050651452629040784,
      0.10109715579595925, 0.2708994887970898,
    ].map((el) => Math.floor(el * 10 ** 12));

    const psi = [
      0.037206384846952066, 0.0915623614722959, 0.16107355519602318,
      0.2824760899898832, 0.35798035117937516,
    ].map((el) => Math.floor(el * 10 ** 12));

    const rho = [
      1.3478910000157727e-8, 2.0145423645807155e-6, 2.910345029369492e-5,
      0.0003768214425074357, 0.0002539234691761822,
    ].map((el) => Math.floor(el * 10 ** 12));

    const tauHex = await f.oracle.formatParams(tau as any);
    const thetaHex = await f.oracle.formatParams(theta as any);
    const psiHex = await f.oracle.formatParams(psi as any);
    const rhoHex = await f.oracle.formatParams(rho as any);

    await f.oracle
      .connect(f.relayer)
      .updateParams([token], [tauHex], [thetaHex], [psiHex], [rhoHex]);

    return { ...f, tau, theta, psi, rho, token };
  }

  describe('#formatParams', () => {
    it('should correctly format parameters', async () => {
      const { oracle } = await loadFixture(deploy);

      const params = await oracle.parseParams(paramsFormatted);
      expect(await oracle.formatParams(params as any)).to.eq(paramsFormatted);
    });

    it('should fail if a variable is out of bounds', async () => {
      const { oracle } = await loadFixture(deploy);

      const newParams = [...params];
      newParams[4] = BigNumber.from(1).shl(51).toString();
      await expect(
        oracle.formatParams(newParams as any),
      ).to.be.revertedWithCustomError(oracle, 'VolatilityOracle__OutOfBounds');
    });
  });

  describe('#parseParams', () => {
    it('should correctly parse parameters', async () => {
      const { oracle } = await loadFixture(deploy);

      const result = await oracle.formatParams(params as any);
      expect(
        (await oracle.parseParams(result)).map((el) => el.toString()),
      ).to.have.same.members(params);
    });
  });

  describe('#findInterval', () => {
    const maturities = [
      0.00273972602739726, 0.03561643835616438, 0.09315068493150686,
      0.16986301369863013, 0.4191780821917808,
    ].map((el) => parseEther(el.toString()));

    it('should correctly find value if in the first interval', async () => {
      const { oracle } = await loadFixture(deploy);

      const v = parseEther('0.02');

      const expected = 0;
      const result = await oracle.findInterval(maturities, v);

      expect(result).to.eq(expected);
    });

    it('should correctly find if a value is in the last interval', async () => {
      const { oracle } = await loadFixture(deploy);

      const v = parseEther('0.3');

      const expected = 3;
      const result = await oracle.findInterval(maturities, v);

      expect(result).to.eq(expected);
    });
  });

  describe('#getVolatility', () => {
    it('should correctly perform short-term extrapolation', async () => {
      const { oracle, token } = await loadFixture(deployAndUpdateParams);

      const spot = parseEther('2800');
      const strike = parseEther('3500');
      const timeToMaturity = parseEther('0.001');

      const iv = await oracle['getVolatility(address,uint256,uint256,uint256)'](
        token,
        spot,
        strike,
        timeToMaturity,
      );
      const result = parseFloat(formatEther(iv));

      const expected = 1.3682433159664105;

      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('should correctly perform interpolation on first interval', async () => {
      const { oracle, token } = await loadFixture(deployAndUpdateParams);

      const spot = parseEther('2800');
      const strike = parseEther('3500');
      const timeToMaturity = parseEther('0.02');

      const iv = await oracle['getVolatility(address,uint256,uint256,uint256)'](
        token,
        spot,
        strike,
        timeToMaturity,
      );
      const result = parseFloat(formatEther(iv));

      const expected = 0.8541332587538256;

      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('should correctly perform interpolation on last interval', async () => {
      const { oracle, token } = await loadFixture(deployAndUpdateParams);

      const spot = parseEther('2800');
      const strike = parseEther('5000');
      const timeToMaturity = parseEther('0.3');

      const iv = await oracle['getVolatility(address,uint256,uint256,uint256)'](
        token,
        spot,
        strike,
        timeToMaturity,
      );
      const result = parseFloat(formatEther(iv));

      const expected = 0.8715627609068288;

      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('should correctly perform long-term extrapolation', async () => {
      const { oracle, token } = await loadFixture(deployAndUpdateParams);

      const spot = parseEther('2800');
      const strike = parseEther('7000');
      const timeToMaturity = parseEther('0.5');

      const iv = await oracle['getVolatility(address,uint256,uint256,uint256)'](
        token,
        spot,
        strike,
        timeToMaturity,
      );
      const result = parseFloat(formatEther(iv));

      const expected = 0.88798013;

      expect(expected / result).to.be.closeTo(1, 0.001);
    });

    it('should correctly perform a batch computation', async () => {
      await prepareContractEnv();

      const spot = parseEther('2800');
      const strike = [
        parseEther('1000'),
        parseEther('2000'),
        parseEther('3000'),
        parseEther('4000'),
        parseEther('5000'),
      ];
      const timeToMaturity = [
        parseEther('0.1'),
        parseEther('0.2'),
        parseEther('0.3'),
        parseEther('0.4'),
        parseEther('0.5'),
      ];

      const iv = await oracle[
        'getVolatility(address,uint256,uint256[],uint256[])'
      ](token, spot, strike, timeToMaturity);
      const result = iv.map((el) => parseFloat(formatEther(el)));

      const expected = [
        1.09666875, 0.83340507, 0.79662759, 0.82515717, 0.84407689,
      ];

      for (let i = 0; i < expected.length; i++) {
        expect(expected[i] / result[i]).to.be.closeTo(1, 0.001);
      }
    });
  });
});
