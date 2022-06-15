require("@nomiclabs/hardhat-waffle");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: "0.8.0",
    networks: {
        rinkeby: {
            url: 'https://eth-rinkeby.alchemyapi.io/v2/Jk5Q0DFO1oXOBWT3sLqpsLpwjGY_Is3v',
            accounts: ['63d6f817dbcb5864da5bb5036947745cc6332998e17b2e38baee83c83103ac19']
        }
    },
    mocha: {
        timeout: 100000000
    }
};
