const express = require('express');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 3000;

// Create a custom metric
const requestCount = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests'
});

app.get('/', (req, res) => {
  requestCount.inc();
  res.send('Hello from Node.js running in a Kubernetes Pod!');
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(port, '0.0.0.0', () => {
  console.log(`App running on http://0.0.0.0:${port}`);
});
 
