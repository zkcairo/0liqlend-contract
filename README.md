# README

0lidlend, a p2p lending app on starknet.

## Flow of use

It's a peer to peer lending apps, so users first `make` orders that other can `take`.
To take an order there is no function in the code, so to do so you need to a multicall that:
+ Create a new offer
+ Add some allowance for the token you use to either lend or as collateral
+ Match your offer with your desired offer
+ Disable you offer if you wish (to avoid being it used again when your loan ends).

To make a lending offer the entrypoint is `make_lending_offer`.
This function won't take your money yet, only when a borrower takes it it will take money from your account.
You therefore need to add some allowance for the token you lend to the contract.

To make a borrowing offer the entrypoint is either `make_borrowing_offer_allowance` or `make_borrowing_offer_deposit`.
The first one create a borrow offer with allowance, where the money is taken from your account
when a lenders takes it. The second will create a borrow offer with a collateral that you already deposited in the platform.

The function `match_offer` match two offers, and can be called by anyone.
Then, `repay_debt` and `liquidate` either repay or liquidate a loan.

## How to run build/tests:

Build: `scarb build`

Run the tests:`snforge test`



## Risks of using the app:

The code is not audited. It could have bugs that could result in total loss of funds.

Starknet and cairo are experimental technology. It could have bugs that could result in total loss of funds.

I reserve the right to modify your number of points at anytime.
Maybe there won't be an airdrop.
Points do not entitle you to a potential airdrop.
I reverse the right to ban you from the points program at anytime.

I am not liable of any loss of funds you may incur when using my app.
By interacting with the app you confirm that you won't sue me for loss of funds or anything else related to my app.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

# Disclaimer of Warranty

The software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.

# Limitation of Liability

In no event shall the authors or copyright holders be liable for any special, incidental, indirect, or consequential damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or any other pecuniary loss) arising out of the use of or inability to use this software, even if the authors or copyright holders have been advised of the possibility of such damages.