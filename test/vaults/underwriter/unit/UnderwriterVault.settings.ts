import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { vaultSetup } from '../UnderwriterVault.fixture';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { formatEther, parseEther, parseUnits } from 'ethers/lib/utils';
import { setMaturities } from '../UnderwriterVault.fixture';
import { ERC20Mock, UnderwriterVaultMock } from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

describe('UnderwriterVault.settings', () => {
  describe('#getSettings', () => {
    it('should get the settings referencing the settings contract', async () => {
      let { deployer, callVault, vaultRegistry } = await loadFixture(
        vaultSetup,
      );

      const settings = await vaultRegistry.getSettings(
        callVault['VAULT_TYPE()'](),
      );
      console.log(await callVault.getTradeBounds());
    });
  });
});
