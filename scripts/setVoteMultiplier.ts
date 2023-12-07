import { VaultMining__factory } from '../typechain';
import { ethers } from 'hardhat';
import { PopulatedTransaction } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import arbitrum from '../deployments/arbitrum/metadata.json';
import { proposeOrSendTransaction } from './utils';

const vaults = [
  {
    name: 'pSV-WETH/USDCe-C',
    address: '0xbae43c546DFADC69576aE73C68e0694A54F08e1B',
    multiplier: parseEther('4'),
  },
  {
    name: 'pSV-WETH/USDCe-P',
    address: '0xD46993F25D298ebbCD31E941156C66f7e628A52a',
    multiplier: parseEther('4'),
  },
  {
    name: 'pSV-WBTC/USDCe-C',
    address: '0x45dF5EA836A15B561937Ae8373ab9eE984aea531',
    multiplier: parseEther('3'),
  },
  {
    name: 'pSV-WBTC/USDCe-P',
    address: '0x6A1FC0E1c60BA6564CDe4910A425F1F1a1d18C1F',
    multiplier: parseEther('3'),
  },
  {
    name: 'pSV-ARB/USDCe-C',
    address: '0xDC631d88dbB5eb39f5c4Bf8B4e5298d098912fFf',
    multiplier: parseEther('3'),
  },
  {
    name: 'pSV-ARB/USDCe-P',
    address: '0xBe3E229319f86F5EE96EE1Dc0B6D55e8b68a439e',
    multiplier: parseEther('3'),
  },
  {
    name: 'pSV-LINK/USDCe-C',
    address: '0x9C9a20b9A27b91592f7EF7622F8c4Fea9f4A0C8f',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-LINK/USDCe-P',
    address: '0x8CEbe7380Bbe5e680Fa31a5fe0229F638580dbf3',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-wstETH/USDCe-C',
    address: '0xe0C92F15eE2947C81e8d72864AC62331bAf8D77d',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-wstETH/USDCe-P',
    address: '0xe330C090e2A5CEB4C39d3fB1dF82c773Efa55dcF',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-GMX/USDCe-C',
    address: '0x2E98Ed9983747ab93F14503cde4Cd0f1EAcBD098',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-GMX/USDCe-P',
    address: '0xB5ECA2280dD6a58C9E17f613F292Cb35E5260f21',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-MAGIC/USDCe-C',
    address: '0xA181F7ce9820b074960C4Ee11d5202F159C87AFB',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-MAGIC/USDCe-P',
    address: '0xe56BF5a095f98c3Ad93ec4C8aa0A5C9bA780b615',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-SOL/USDCe-C',
    address: '0x2aebD7FFd70cB191eb72a76662a04aEb6A4Ee9E2',
    multiplier: parseEther('1'),
  },
  {
    name: 'pSV-SOL/USDCe-P',
    address: '0x010aEb3ec7A6a15655C2991eb617c7D9b64Baef0',
    multiplier: parseEther('1'),
  },
];

async function main() {
  const [deployer, proposer] = await ethers.getSigners();

  const instance = VaultMining__factory.connect(
    arbitrum.core.VaultMiningProxy.address,
    deployer,
  );

  const transactions: PopulatedTransaction[] = [];
  for (const vault of vaults) {
    transactions.push(
      await instance.populateTransaction.setVoteMultiplier(
        vault.address,
        vault.multiplier,
      ),
    );
  }

  await proposeOrSendTransaction(
    true,
    arbitrum.addresses.treasury,
    proposer,
    transactions,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
