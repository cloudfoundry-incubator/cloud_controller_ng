### Delete a service broker

```
Example Request
```

```shell
curl "https://api.example.org/v3/service_brokers/[guid]" \
  -X DELETE \
  -H "Authorization: bearer [token]"
```

```
Example Response
```

```http
HTTP/1.1 204 No Content
```

This endpoint deletes the service broker by GUID.

#### Definition
`DELETE /v3/service_brokers/:guid`

#### Permitted Roles
 |
--- | ---
Space Developer |
Admin |
