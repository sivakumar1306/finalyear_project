# DESIGN.md

# Vital Monitoring App Design System

## Product Vision

Vital Monitoring is a premium smart ring companion application focused on health, recovery, wellness, and daily insights.

The visual language should feel:

- Premium
- Minimal
- Calm
- Scientific
- Trustworthy
- Luxury healthcare

The interface should avoid bright colors, flat surfaces, and overly playful elements.

The app should feel closer to Whoop, Oura, and Apple Health than a fitness tracker app.

---

# Core Design Principles

## 1. Information First

Health data is the hero.

Visual effects should support the data, never overpower it.

Users should be able to identify:

- Heart Rate
- Sleep
- Stress
- HRV
- Blood Oxygen
- Blood Pressure
- Temperature

within 1 second of opening the screen.

---

## 2. Premium Dark Theme

The application is permanently dark themed.

No light mode support.

### App Background

```css
rgb(5, 5, 5)
#050505
```

Used on:

- App scaffold
- Detail screens
- Bottom navigation background
- Modal backgrounds

---

## 3. Soft Glassmorphism

Cards and controls use subtle glass effects.

Avoid:

- Strong shadows
- Hard borders
- Sharp gradients

Use:

- Soft blur
- Transparent surfaces
- Ambient glow

---

## Color System

### Primary Accent

Used for:

- CTA buttons
- Important values
- Voice assistant
- Selection states
- Active indicators

```css
#C9A86E
rgb(201, 168, 110)
```

---

### Text Colors

#### Primary Text

```css
rgba(255,255,255,0.95)
```

Used for:

- Metric values
- Screen titles
- Important content

---

#### Secondary Text

```css
rgba(255,255,255,0.65)
```

Used for:

- Labels
- Supporting content
- Units

---

#### Tertiary Text

```css
rgba(255,255,255,0.35)
```

Used for:

- Captions
- Trend labels
- Metadata

---

# Card System

Every health card follows the same structure.

## Card Container

Background:

```css
rgba(255,255,255,0.06)
```

Border:

```css
0.5px solid rgba(255,255,255,0.09)
```

Blur:

```css
backdrop-filter: blur(28px)
```

Border Radius:

```css
20px
```

Padding:

```css
16px
```

---

## Orb Glow

Each card contains one ambient orb.

Purpose:

- Creates depth
- Helps differentiate metrics

Orb Settings:

```css
layer blur: 70px
opacity: 40%-60%
```

Orb should never obstruct content.

---

# Metric Colors

Different health metrics use different orb colors.

The values below are the **active** tokens defined in `AppTheme` (`lib/theme/app_theme.dart`) and used
everywhere: detail-screen charts, stat values, legends, and ambient orbs. The older **soft** palette
(`#C96B6B`, `#6B82D9`, `#6BC99B`, `#C9A86E`, `#73D4F8`, `#D97A7A`, `#E3B76A`, `#D88CC8`) was a
Phase-3 mistake that muted these tokens; it is no longer used. Do not reintroduce it.

## Heart Rate

```css
#FF4757
```

Bright red.

---

## Sleep

```css
#8B5CF6
```

Violet.

---

## Stress

```css
#F97316
```

Orange.

---

## HRV

```css
#2DD4BF
```

Teal.

---

## Blood Oxygen

```css
#38BDF8
```

Sky blue.

---

## Blood Pressure

```css
#818CF8
```

Indigo.

---

## Temperature

```css
#FBBF24
```

Amber.

---

## Women's Health

```css
#EC4899
```

Pink.

---

## Steps

```css
#F59E0B
```

Amber.

---

# Component Styling

## Buttons

Used for:

- Start Measurement
- Actions
- Navigation

Background:

```css
rgba(255,255,255,0.03)
```

Border:

```css
0.5px solid rgba(255,255,255,0.08)
```

Blur:

```css
28px
```

Radius:

```css
999px
```

Height:

```css
44px - 52px
```

---

## Icon Buttons

Circular glass buttons.

Size:

```css
36px - 40px
```

Background:

```css
rgba(255,255,255,0.03)
```

Border:

```css
rgba(255,255,255,0.08)
```

---

## Toggles

### Selected State

```css
rgba(255,255,255,0.08)
```

### Unselected State

```css
rgba(255,255,255,0.03)
```

Border:

```css
rgba(255,255,255,0.08)
```

---

# Typography

## Screen Title

```css
24px
Font Weight 600
```

Examples:

- Heart Rate
- Blood Oxygen
- Sleep

---

## Metric Value

```css
36px - 48px
Font Weight 300
```

Examples:

- 72 BPM
- 98%
- 67

These should dominate the card.

---

## Card Title

```css
14px
Font Weight 500
```

Examples:

- Heart Rate
- Sleep
- Stress

---

## Supporting Text

```css
12px
Font Weight 400
```

Examples:

- Normal
- Daily Average
- Weekly Trend

---

# Dashboard Layout

## Home Screen

Order:

1. Greeting Header
2. Ring Status Card
3. Alarm Card
4. Activity Card
5. Stress Card
6. Sleep Card
7. HRV Card
8. Blood Oxygen Card
9. Heart Rate Card
10. Sport Card
11. Women's Health Card
12. Temperature Card
13. Blood Pressure Card

---

## Card Hierarchy

Large cards:

- Stress
- Heart Rate
- Sleep Detail
- AI Insights

Medium cards:

- Blood Pressure
- Women's Health

Small cards:

- HRV
- Temperature
- Blood Oxygen

---

# Graph Design

Graphs should feel subtle and premium.

Avoid:

- Bright chart colors
- Thick strokes
- Busy grids

Use:

- 1-2px strokes
- Soft opacity
- Faded grid lines

Grid Lines:

```css
rgba(255,255,255,0.05)
```

Graph Stroke:

```css
rgba(255,255,255,0.7)
```

Accent highlights:

Metric-specific color.

---

# Detail Pages

All metric detail pages follow the same layout.

## Structure

1. Navigation Header
2. Date Selector
3. Current Reading
4. Primary Chart
5. Statistics Cards
6. Measurement CTA
7. Trend Section
8. Historical Insights

Examples:

- Heart Rate Detail
- Blood Oxygen Detail
- Sleep Detail

Must maintain consistency.

---

# Voice Assistant

Voice assistant is a flagship feature.

Visual goals:

- Premium
- Futuristic
- Calm

Use:

- Large gold microphone
- Concentric glow rings
- Gold waveform animation

Primary Accent:

```css
#C9A86E
```

---

# Motion Guidelines

Animations should feel slow and luxurious.

### Preferred Duration

```css
200ms - 400ms
```

### Avoid

- Bounce
- Elastic
- Spring-heavy interactions

### Preferred

- Fade
- Blur transitions
- Scale 0.98 → 1.0
- Smooth card elevation

---

# Developer Rules

Always follow these rules:

1. Never use pure white backgrounds.
2. Never use bright saturated colors.
3. Every card must use glass styling.
4. Every health metric card must have an ambient orb.
5. Use #C9A86E as the only primary accent color.
6. Maintain consistent spacing and radius.
7. Charts must remain subtle and data-focused.
8. UI should feel closer to Oura than a traditional fitness tracker.
9. Prioritize readability over visual effects.
10. Do not introduce new colors without design approval.

---

# Reference Screens

Reference designs include:

- Home Dashboard
- Heart Rate Detail
- Blood Oxygen Detail
- Sleep Detail
- Stress Card
- Blood Pressure Card
- Women's Health Card
- Alarm Modes
- AI Voice Assistant

All future UI work must visually align with these references.