# Yield strategy contract

Yield project created on the **Rinkeby network**. Deposits & withdrawals are happening with **Uniswap V3: Router2** and **Aave** contracts integrations.

#### Deposits breakdown ( buyAndDeposit method ):
* The ```msg.sender``` is passing X amount of ETH value.
* The method is calculating how much USDC token can be purchased from Uniswap V3 for the passed ETH value.
* The method is buying USDC token equivalent of the passed ETH value from Uniswap V3.
* The method is depositing the USDC tokens on behalf of the ```msg.sender``` to Aave platform using the ```Aave.supply()``` method.

#### Withdrawals breakdown ( withdraw() & withdraw(uint256) methods ):
* The ```msg.sender``` is passing what amount of USDC he wishes to withdraw.
* The method is withdrawing the USDC tokens from Aave platform using the ```Aave.withdraw()``` method.
* The method is calculating how much ETH value can be purchased for the withdrawn USDC tokens from Aave.
* The method is selling the USDC tokens against ETH value at Uniswap V3.
* The method is charging the ```msg.sender``` with withdrawal fee ( in ETH ) and submitting the fee to the YieldContract owner.
* The method is sending the rest of ETH back to the ```msg.sender```.

#### Commands:
* ```npm install``` - Downloading required packages.
* ```npx hardhat run scripts/deploy.js --network rinkeby``` - Deploying the contract on the Rinkeby network.
* ```npx hardhat test --network rinkeby``` - Firing the tests on the Rinkeby network.
* ```slither . --json slither.txt``` - slither.txt report already exist in the root, but if for whatever reason the report has to be generated again it can be achieved with this command.

#### FYI:
There are dummy private key ( with 1 rETH ) and Rinkeby node at the ```hardhat.config.js```.