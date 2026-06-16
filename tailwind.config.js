/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: {
          50: "#f8f6f3",
          100: "#f0ece5",
          200: "#e0d6c8",
          300: "#cdbba5",
          400: "#b89d80",
          500: "#a88666",
          600: "#9b7559",
          700: "#815f4b",
          800: "#6a4f41",
          900: "#574237",
          950: "#2e211c",
        },
        paper: {
          50: "#fefdfb",
          100: "#fdf9f3",
          200: "#faf2e6",
          300: "#f5e8d3",
          400: "#eed9bc",
          500: "#e5c7a0",
        },
        xuan: {
          DEFAULT: "#1a1a1a",
          light: "#2d2d2d",
          dark: "#0d0d0d",
        },
      },
      fontFamily: {
        serif: ['"Noto Serif SC"', '"Source Han Serif SC"', "STSong", "serif"],
        brush: ['"Ma Shan Zheng"', '"ZCOOL KuaiLe"', "cursive"],
      },
      backgroundImage: {
        "paper-texture":
          'url("data:image/svg+xml,%3Csvg width=\'100\' height=\'100\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cfilter id=\'noise\'%3E%3CfeTurbulence type=\'fractalNoise\' baseFrequency=\'0.65\' numOctaves=\'3\' stitchTiles=\'stitch\'/%3E%3C/filter%3E%3Crect width=\'100%25\' height=\'100%25\' filter=\'url(%23noise)\' opacity=\'0.05\'/%3E%3C/svg%3E")',
      },
      boxShadow: {
        ink: "2px 2px 8px rgba(30, 20, 10, 0.3)",
        "ink-lg": "4px 4px 16px rgba(30, 20, 10, 0.4)",
      },
    },
  },
  plugins: [],
};
