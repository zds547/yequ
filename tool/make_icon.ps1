# 生成「夜曲」阅读器图标：深夜蓝渐变底 + 金色新月 + 摊开的书 + 星光。
# 输出 1024 主图与 Android 各密度 mipmap PNG。
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class YequIcon {
  static float S(float v, float k) { return v * k; }

  static GraphicsPath RoundRect(float size, float r) {
    var p = new GraphicsPath();
    float d = r * 2;
    p.AddArc(0, 0, d, d, 180, 90);
    p.AddArc(size - d, 0, d, d, 270, 90);
    p.AddArc(size - d, size - d, d, d, 0, 90);
    p.AddArc(0, size - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }

  static void Star(Graphics g, Brush b, float cx, float cy, float r) {
    PointF[] pts = new PointF[] {
      new PointF(cx, cy - r),
      new PointF(cx + r * 0.28f, cy - r * 0.28f),
      new PointF(cx + r, cy),
      new PointF(cx + r * 0.28f, cy + r * 0.28f),
      new PointF(cx, cy + r),
      new PointF(cx - r * 0.28f, cy + r * 0.28f),
      new PointF(cx - r, cy),
      new PointF(cx - r * 0.28f, cy - r * 0.28f),
    };
    g.FillPolygon(b, pts);
  }

  public static Bitmap Render(int size) {
    float k = size / 1024f;
    var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;

      var c1 = Color.FromArgb(255, 38, 52, 116);
      var c2 = Color.FromArgb(255, 12, 18, 44);
      using (var grad = new LinearGradientBrush(
                 new PointF(0, 0), new PointF(size, size), c1, c2))
      using (var path = RoundRect(size, S(230, k))) {
        g.FillPath(grad, path);
        g.SetClip(path);

        // soft glow behind the moon
        using (var glow = new SolidBrush(Color.FromArgb(70, 120, 140, 220)))
          g.FillEllipse(glow, S(150, k), S(90, k), S(720, k), S(720, k));

        // sparkles
        using (var sb = new SolidBrush(Color.FromArgb(255, 255, 244, 205))) {
          Star(g, sb, S(232, k), S(286, k), S(30, k));
          Star(g, sb, S(792, k), S(232, k), S(22, k));
          Star(g, sb, S(806, k), S(540, k), S(16, k));
          Star(g, sb, S(262, k), S(566, k), S(18, k));
          Star(g, sb, S(668, k), S(138, k), S(13, k));
          Star(g, sb, S(168, k), S(430, k), S(10, k));
        }

        // crescent: gold disc cut by an offset background-gradient circle
        float mcx = S(512, k), mcy = S(418, k), mr = S(208, k);
        using (var gold = new SolidBrush(Color.FromArgb(255, 244, 201, 96)))
          g.FillEllipse(gold, mcx - mr, mcy - mr, mr * 2, mr * 2);
        float cr = S(182, k), ccx = mcx + S(86, k), ccy = mcy - S(92, k);
        g.FillEllipse(grad, ccx - cr, ccy - cr, cr * 2, cr * 2);

        // open book: cover and two pages
        PointF[] cover = new PointF[] {
          new PointF(S(196, k), S(706, k)),
          new PointF(S(512, k), S(652, k)),
          new PointF(S(828, k), S(706, k)),
          new PointF(S(828, k), S(878, k)),
          new PointF(S(512, k), S(926, k)),
          new PointF(S(196, k), S(878, k)),
        };
        using (var cb = new SolidBrush(Color.FromArgb(255, 201, 158, 74)))
          g.FillPolygon(cb, cover);

        PointF[] left = new PointF[] {
          new PointF(S(226, k), S(724, k)),
          new PointF(S(496, k), S(684, k)),
          new PointF(S(496, k), S(884, k)),
          new PointF(S(226, k), S(850, k)),
        };
        PointF[] right = new PointF[] {
          new PointF(S(528, k), S(684, k)),
          new PointF(S(798, k), S(724, k)),
          new PointF(S(798, k), S(850, k)),
          new PointF(S(528, k), S(884, k)),
        };
        using (var pb = new SolidBrush(Color.FromArgb(255, 247, 236, 212))) {
          g.FillPolygon(pb, left);
          g.FillPolygon(pb, right);
        }
        using (var spine = new Pen(Color.FromArgb(180, 168, 128, 64), S(5, k)))
          g.DrawLine(spine, S(512, k), S(678, k), S(512, k), S(906, k));
        using (var ln = new Pen(Color.FromArgb(70, 120, 96, 60), S(6, k))) {
          g.DrawLine(ln, S(268, k), S(762, k), S(462, k), S(734, k));
          g.DrawLine(ln, S(268, k), S(800, k), S(462, k), S(772, k));
          g.DrawLine(ln, S(562, k), S(734, k), S(756, k), S(762, k));
          g.DrawLine(ln, S(562, k), S(772, k), S(756, k), S(800, k));
        }
      }
    }
    return bmp;
  }

  public static void SaveAll(string root) {
    using (var master = Render(1024)) {
      master.Save(Path.Combine(root, "icon_master.png"), ImageFormat.Png);
      string[][] sizes = new string[][] {
        new string[] { "mipmap-mdpi", "48" },
        new string[] { "mipmap-hdpi", "72" },
        new string[] { "mipmap-xhdpi", "96" },
        new string[] { "mipmap-xxhdpi", "144" },
        new string[] { "mipmap-xxxhdpi", "192" },
      };
      foreach (string[] item in sizes) {
        string dir = item[0];
        int px = int.Parse(item[1]);
        using (var small = Render(px)) {
          string p = Path.Combine(root,
            "android", "app", "src", "main", "res", dir, "ic_launcher.png");
          small.Save(p, ImageFormat.Png);
          Console.WriteLine("wrote " + dir + " (" + px + "px)");
        }
      }
    }
  }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing
[YequIcon]::SaveAll('d:\code\yequ')
