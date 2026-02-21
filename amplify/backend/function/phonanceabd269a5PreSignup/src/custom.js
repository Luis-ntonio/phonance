/**
 * @type {import('@types/aws-lambda').APIGatewayProxyHandler}
 */
const {
  CognitoIdentityProviderClient,
  ListUsersCommand,
} = require("@aws-sdk/client-cognito-identity-provider");

const client = new CognitoIdentityProviderClient({});

exports.handler = async (event) => {
  const phone = event?.request?.userAttributes?.phone_number;

  if (!phone) {
    throw new Error("Phone number is required.");
  }

  const userPoolId = event.userPoolId;

  const cmd = new ListUsersCommand({
    UserPoolId: userPoolId,
    Filter: `phone_number = "${phone}"`,
    Limit: 1,
  });

  const res = await client.send(cmd);

  if (res.Users && res.Users.length > 0) {
    throw new Error("Phone number already in use.");
  }

  return event;
};
