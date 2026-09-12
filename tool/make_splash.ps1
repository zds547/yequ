# 生成「夜曲」启动页居中 Logo（透明底：新月 + 摊开的书 + 星光 + 夜曲二字）。
# 由 launch_background.xml 以 center gravity 放在夜空渐变之上。
# 输出到 drawable-nodpi，避免系统按密度缩放，各分辨率共用同一张位图。
Add-Type -AssemblyName System.Drawing

$code = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class YequSplash {
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

  // Icon artwork lives in a 1024 box; map the book (icon center 512,789)
  // into the splash canvas with uniform scale 0.46 and center (240, 352).
  static float BX(float x) { return (x - 512f) * 0.46f + 240f; }
  static float BY(float y) { return (y - 789f) * 0.46f + 352f; }

  static FontFamily PickFont() {
    string[] names = new string[] { "KaiTi", "STKaiti", "STSong", "SimSun", "Microsoft YaHei" };
    foreach (string n in names) {
      try {
        var f = new FontFamily(n);
        if (f != null) return f;
      } catch { }
    }
    return FontFamily.GenericSerif;
  }

  public static Bitmap Render() {
    const int W = 480, H = 600;
    var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

      // crescent geometry
      float mcx = 240f, mcy = 150f, mr = 96f;
      float cr = 84f, ccx = mcx + 40f, ccy = mcy - 42f;

      // soft glow behind the moon
      using (var glow = new SolidBrush(Color.FromArgb(60, 120, 140, 220)))
        g.FillEllipse(glow, 96, 10, 288, 288);
      // erase glow where the crescent will be cut, so the hole is fully transparent
      var oldMode = g.CompositingMode;
      g.CompositingMode = CompositingMode.SourceCopy;
      using (var eraser = new SolidBrush(Color.FromArgb(0, 0, 0, 0)))
        g.FillEllipse(eraser, ccx - cr, ccy - cr, cr * 2, cr * 2);
      g.CompositingMode = oldMode;

      // sparkles
      using (var sb = new SolidBrush(Color.FromArgb(255, 255, 244, 205))) {
        Star(g, sb, 96, 118, 13);
        Star(g, sb, 386, 96, 10);
        Star(g, sb, 392, 250, 8);
        Star(g, sb, 84, 268, 8);
      }

      // crescent: gold disc with an offset hole (alternate path subtracts it)
      using (var gold = new SolidBrush(Color.FromArgb(255, 244, 201, 96)))
      using (var cres = new GraphicsPath(FillMode.Alternate)) {
        cres.AddEllipse(mcx - mr, mcy - mr, mr * 2, mr * 2);
        cres.AddEllipse(ccx - cr, ccy - cr, cr * 2, cr * 2);
        g.FillPath(gold, cres);
      }

      // open book: cover + two pages, scaled from the icon artwork
      PointF[] cover = new PointF[] {
        new PointF(BX(196), BY(706)),
        new PointF(BX(512), BY(652)),
        new PointF(BX(828), BY(706)),
        new PointF(BX(828), BY(878)),
        new PointF(BX(512), BY(926)),
        new PointF(BX(196), BY(878)),
      };
      using (var cb = new SolidBrush(Color.FromArgb(255, 201, 158, 74)))
        g.FillPolygon(cb, cover);

      PointF[] left = new PointF[] {
        new PointF(BX(226), BY(724)),
        new PointF(BX(496), BY(684)),
        new PointF(BX(496), BY(884)),
        new PointF(BX(226), BY(850)),
      };
      PointF[] right = new PointF[] {
        new PointF(BX(528), BY(684)),
        new PointF(BX(798), BY(724)),
        new PointF(BX(798), BY(850)),
        new PointF(BX(528), BY(884)),
      };
      using (var pb = new SolidBrush(Color.FromArgb(255, 247, 236, 212))) {
        g.FillPolygon(pb, left);
        g.FillPolygon(pb, right);
      }
      using (var spine = new Pen(Color.FromArgb(180, 168, 128, 64), 2.4f))
        g.DrawLine(spine, BX(512), BY(678), BX(512), BY(906));
      using (var ln = new Pen(Color.FromArgb(70, 120, 96, 60), 2.6f)) {
        g.DrawLine(ln, BX(268), BY(762), BX(462), BY(734));
        g.DrawLine(ln, BX(268), BY(800), BX(462), BY(772));
        g.DrawLine(ln, BX(562), BY(734), BX(756), BY(762));
        g.DrawLine(ln, BX(562), BY(772), BX(756), BY(800));
      }

      // app name: two spaced characters in an elegant serif/calligraphic face
      using (var family = PickFont())
      using (var font = new Font(family, 58f, FontStyle.Bold, GraphicsUnit.Pixel))
      using (var tg = new SolidBrush(Color.FromArgb(255, 244, 201, 96)))
      using (var fmt = new StringFormat()) {
        fmt.Alignment = StringAlignment.Center;
        fmt.LineAlignment = StringAlignment.Center;
        g.DrawString("\u591C", font, tg, new RectangleF(176, 452, 64, 80), fmt);
        g.DrawString("\u66F2", font, tg, new RectangleF(240, 452, 64, 80), fmt);
      }
    }
    return bmp;
  }

  // Android 12+ splash icon: square canvas, emblem kept inside the center
  // circle (system shows the drawable within a circular safe area).
  static float EX(float x) { return (x - 512f) * 0.72f + 480f; }
  static float EY(float y) { return (y - 789f) * 0.72f + 640f; }

  public static Bitmap RenderEmblem() {
    var bmp = new Bitmap(960, 960, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;

      float mcx = 480f, mcy = 400f, mr = 165f;
      float cr = 145f, ccx = mcx + 68f, ccy = mcy - 72f;

      using (var glow = new SolidBrush(Color.FromArgb(48, 120, 140, 220)))
        g.FillEllipse(glow, mcx - 250, mcy - 250, 500, 500);
      var oldMode = g.CompositingMode;
      g.CompositingMode = CompositingMode.SourceCopy;
      using (var eraser = new SolidBrush(Color.FromArgb(0, 0, 0, 0)))
        g.FillEllipse(eraser, ccx - cr, ccy - cr, cr * 2, cr * 2);
      g.CompositingMode = oldMode;

      using (var sb = new SolidBrush(Color.FromArgb(255, 255, 244, 205))) {
        Star(g, sb, 250, 330, 20);
        Star(g, sb, 720, 300, 15);
      }

      using (var gold = new SolidBrush(Color.FromArgb(255, 244, 201, 96)))
      using (var cres = new GraphicsPath(FillMode.Alternate)) {
        cres.AddEllipse(mcx - mr, mcy - mr, mr * 2, mr * 2);
        cres.AddEllipse(ccx - cr, ccy - cr, cr * 2, cr * 2);
        g.FillPath(gold, cres);
      }

      PointF[] cover = new PointF[] {
        new PointF(EX(196), EY(706)),
        new PointF(EX(512), EY(652)),
        new PointF(EX(828), EY(706)),
        new PointF(EX(828), EY(878)),
        new PointF(EX(512), EY(926)),
        new PointF(EX(196), EY(878)),
      };
      using (var cb = new SolidBrush(Color.FromArgb(255, 201, 158, 74)))
        g.FillPolygon(cb, cover);
      PointF[] left = new PointF[] {
        new PointF(EX(226), EY(724)),
        new PointF(EX(496), EY(684)),
        new PointF(EX(496), EY(884)),
        new PointF(EX(226), EY(850)),
      };
      PointF[] right = new PointF[] {
        new PointF(EX(528), EY(684)),
        new PointF(EX(798), EY(724)),
        new PointF(EX(798), EY(850)),
        new PointF(EX(528), EY(884)),
      };
      using (var pb = new SolidBrush(Color.FromArgb(255, 247, 236, 212))) {
        g.FillPolygon(pb, left);
        g.FillPolygon(pb, right);
      }
      using (var spine = new Pen(Color.FromArgb(180, 168, 128, 64), 3.6f))
        g.DrawLine(spine, EX(512), EY(678), EX(512), EY(906));
      using (var ln = new Pen(Color.FromArgb(70, 120, 96, 60), 4f)) {
        g.DrawLine(ln, EX(268), EY(762), EX(462), EY(734));
        g.DrawLine(ln, EX(268), EY(800), EX(462), EY(772));
        g.DrawLine(ln, EX(562), EY(734), EX(756), EY(762));
        g.DrawLine(ln, EX(562), EY(772), EX(756), EY(800));
      }
    }
    return bmp;
  }

  // Bottom brand image for Android 12+: gold wordmark on transparent.
  public static Bitmap RenderWordmark() {
    var bmp = new Bitmap(480, 150, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
      using (var family = PickFont())
      using (var font = new Font(family, 88f, FontStyle.Bold, GraphicsUnit.Pixel))
      using (var tg = new SolidBrush(Color.FromArgb(255, 244, 201, 96)))
      using (var fmt = new StringFormat()) {
        fmt.Alignment = StringAlignment.Center;
        fmt.LineAlignment = StringAlignment.Center;
        g.DrawString("\u591C", font, tg, new RectangleF(152, 0, 96, 150), fmt);
        g.DrawString("\u66F2", font, tg, new RectangleF(232, 0, 96, 150), fmt);
      }
    }
    return bmp;
  }

  public static void SaveAll(string resDir, string assetDir) {
    if (!Directory.Exists(resDir)) Directory.CreateDirectory(resDir);
    using (var bmp = Render()) {
      bmp.Save(Path.Combine(resDir, "splash_logo.png"), ImageFormat.Png);
      if (assetDir != null) {
        if (!Directory.Exists(assetDir)) Directory.CreateDirectory(assetDir);
        bmp.Save(Path.Combine(assetDir, "splash_logo.png"), ImageFormat.Png);
      }
    }
    using (var bmp = RenderEmblem())
      bmp.Save(Path.Combine(resDir, "splash_emblem.png"), ImageFormat.Png);
    using (var bmp = RenderWordmark())
      bmp.Save(Path.Combine(resDir, "splash_wordmark.png"), ImageFormat.Png);
    Console.WriteLine("wrote splash assets to " + resDir);
  }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing
[YequSplash]::SaveAll('d:\code\yequ\android\app\src\main\res\drawable-nodpi', 'd:\code\yequ\assets\images')
