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
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Welcome to the Golden Path!</title>
      <style>
        body {
          background: #181818;
          color: #fff;
          font-family: 'Segoe UI', Arial, sans-serif;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100vh;
          margin: 0;
        }
        h1 {
          font-size: 2.5rem;
          margin-bottom: 0.5em;
        }
        .subtitle {
          font-size: 1.3rem;
          margin-bottom: 2em;
        }
        #crackers {
          position: absolute;
          top: 0;
          left: 0;
          width: 100vw;
          height: 100vh;
          pointer-events: none;
          z-index: 0;
        }
        .content {
          z-index: 1;
          position: relative;
          text-align: center;
        }
      </style>
    </head>
    <body>
      <canvas id="crackers"></canvas>
      <div class="content">
        <h1>✨🚀🎉 Welcome to the Golden Path! 🎉🚀✨</h1>
        <div class="subtitle">🎈 Deploying your Node.js application inside a blazing Kubernetes Pod! 🔥</div>
      </div>
      <script>
        // Simple crackers/fireworks animation
        const canvas = document.getElementById('crackers');
        const ctx = canvas.getContext('2d');
        let W = window.innerWidth;
        let H = window.innerHeight;
        canvas.width = W;
        canvas.height = H;
        window.addEventListener('resize', () => {
          W = window.innerWidth;
          H = window.innerHeight;
          canvas.width = W;
          canvas.height = H;
        });
        function randomColor() {
          return `hsl(${Math.random()*360}, 100%, 60%)`;
        }
        function Firework() {
          this.x = Math.random() * W;
          this.y = H;
          this.targetY = Math.random() * H * 0.5 + 50;
          this.color = randomColor();
          this.radius = 2 + Math.random() * 2;
          this.exploded = false;
          this.particles = [];
        }
        Firework.prototype.update = function() {
          if (!this.exploded) {
            this.y -= 8;
            if (this.y <= this.targetY) {
              this.exploded = true;
              for (let i = 0; i < 30; i++) {
                const angle = (Math.PI * 2 * i) / 30;
                const speed = Math.random() * 4 + 2;
                this.particles.push({
                  x: this.x,
                  y: this.y,
                  vx: Math.cos(angle) * speed,
                  vy: Math.sin(angle) * speed,
                  alpha: 1,
                  color: this.color
                });
              }
            }
          } else {
            this.particles.forEach(p => {
              p.x += p.vx;
              p.y += p.vy;
              p.vy += 0.05;
              p.alpha -= 0.015;
            });
            this.particles = this.particles.filter(p => p.alpha > 0);
          }
        };
        Firework.prototype.draw = function(ctx) {
          if (!this.exploded) {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
            ctx.fillStyle = this.color;
            ctx.fill();
          } else {
            this.particles.forEach(p => {
              ctx.save();
              ctx.globalAlpha = p.alpha;
              ctx.beginPath();
              ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
              ctx.fillStyle = p.color;
              ctx.fill();
              ctx.restore();
            });
          }
        };
        let fireworks = [];
        function animate() {
          ctx.clearRect(0, 0, W, H);
          if (Math.random() < 0.04) {
            fireworks.push(new Firework());
          }
          fireworks.forEach(fw => {
            fw.update();
            fw.draw(ctx);
          });
          fireworks = fireworks.filter(fw => !fw.exploded || fw.particles.length > 0);
          requestAnimationFrame(animate);
        }
        animate();
      </script>
    </body>
    </html>
  `);
 
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(port, '0.0.0.0', () => {
  console.log(`App running on http://0.0.0.0:${port}`);
});
 
