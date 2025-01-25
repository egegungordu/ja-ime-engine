/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ["class"],
  content: ["./index.html", "./src/**/*.{ts,tsx,js,jsx}"],
  theme: {
    extend: {
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      fontFamily: {
        sans: ["var(--font-sans)"],
      },
      colors: {
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        chart: {
          1: "hsl(var(--chart-1))",
          2: "hsl(var(--chart-2))",
          3: "hsl(var(--chart-3))",
          4: "hsl(var(--chart-4))",
          5: "hsl(var(--chart-5))",
        },
        "red-primary": "hsl(var(--red-primary))",
        "red-secondary": "hsl(var(--red-secondary))",
        "orange-primary": "hsl(var(--orange-primary))",
        "orange-secondary": "hsl(var(--orange-secondary))",
        "yellow-primary": "hsl(var(--yellow-primary))",
        "yellow-secondary": "hsl(var(--yellow-secondary))",
        "green-primary": "hsl(var(--green-primary))",
        "green-secondary": "hsl(var(--green-secondary))",
        "cyan-primary": "hsl(var(--cyan-primary))",
        "cyan-secondary": "hsl(var(--cyan-secondary))",
        "blue-primary": "hsl(var(--blue-primary))",
        "blue-secondary": "hsl(var(--blue-secondary))",
        "purple-primary": "hsl(var(--purple-primary))",
        "purple-secondary": "hsl(var(--purple-secondary))",
        "magenta-primary": "hsl(var(--magenta-primary))",
        "magenta-secondary": "hsl(var(--magenta-secondary))",
        highlight: "hsl(var(--highlight))",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};
