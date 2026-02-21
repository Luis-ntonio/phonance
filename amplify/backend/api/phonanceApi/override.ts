import { AmplifyApiRestResourceStackTemplate } from "@aws-amplify/cli-extensibility-helper";

export function override(resources: AmplifyApiRestResourceStackTemplate) {
  // 1) Reemplaza con el nombre EXACTO de la carpeta en amplify/backend/auth/
  const authResourceName = "phonanceabd269a5"; // ejemplo: "phonanceAuthXXXX"
  const userPoolArnParameter = "AuthCognitoUserPoolArn";

  // 2) Param con el ARN del User Pool (sale del recurso Auth del proyecto)
  resources.addCfnParameter(
    {
      type: "String",
      description: "The ARN of an existing Cognito User Pool to authorize requests",
      default: "NONE",
    },
    userPoolArnParameter,
    { "Fn::GetAtt": [`auth${authResourceName}`, "Outputs.UserPoolArn"] }
  );

  // 3) Define el authorizer en OpenAPI (securityDefinitions)
  resources.restApi.addPropertyOverride("Body.securityDefinitions", {
    Cognito: {
      type: "apiKey",
      name: "Authorization",
      in: "header",
      "x-amazon-apigateway-authtype": "cognito_user_pools",
      "x-amazon-apigateway-authorizer": {
        type: "cognito_user_pools",
        providerARNs: [{ "Fn::Join": ["", [{ Ref: userPoolArnParameter }]] }],
      },
    },
  });

  // 4) Aplica seguridad SOLO a /profile (y no a OPTIONS)
  const protectedPaths = ["/profile", "/expenses", "/subscription", "/auth", "/getMPlink", '/subscription/refresh', '/subscription/cancel', '/subscription/summary'];

  for (const path of protectedPaths) {
    const pathObj = resources.restApi.body.paths?.[path];
    if (!pathObj) continue;

    for (const methodKey of Object.keys(pathObj)) {
      if (methodKey.toLowerCase() === "options") continue;

      // Si Amplify usa x-amazon-apigateway-any-method
      const isAny = methodKey === "x-amazon-apigateway-any-method";
      const methodPath = isAny
        ? `Body.paths.${path}.x-amazon-apigateway-any-method`
        : `Body.paths.${path}.${methodKey}`;

      // Asegura que exista "parameters" (añade Authorization header)
      const existingParams = (pathObj[methodKey]?.parameters ?? []) as any[];

      resources.restApi.addPropertyOverride(`${methodPath}.parameters`, [
        ...existingParams,
        {
          name: "Authorization",
          in: "header",
          required: false,
          type: "string",
        },
      ]);

      // Activa el authorizer
      resources.restApi.addPropertyOverride(`${methodPath}.security`, [{ Cognito: [] }]);


    }
  }
}
