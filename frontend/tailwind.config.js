/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        obsidian: '#070913',
        panel: '#0f1424',
        panelBorder: '#1e2942',
      },
    },
  },
  plugins: [],
};
