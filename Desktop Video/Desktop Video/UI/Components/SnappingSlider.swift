//
//  SnappingSlider.swift
//  Desktop Video
//
//  带「磁吸刻度」的滑块：在 0 / 25 / 50 / 75 / 100 等档位附近会自动吸附（trap）。
//  自绘轨道 + 已填充 + 刻度点 + 拇指 + 档位标签，保证「拇指中心」与「档位标签」严格对齐
//  ——原生 SwiftUI Slider 的拇指内缩量（knob inset）未公开，故外部标签无法与其精确对齐，
//  这也是把它换成自绘组件的原因。
//

import SwiftUI

struct SnappingSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    /// 磁吸档位（与 value 同单位）。
    var traps: [Double] = [0, 25, 50, 75, 100]
    /// 距离档位多近时吸附。
    var snapRadius: Double = 4
    /// 是否在轨道下方显示档位标签。
    var showsLabels: Bool = true
    /// 档位标签文案。
    var labelText: (Double) -> String = { "\(Int($0))%" }

    @Environment(\.theme) private var theme

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 18
    private let labelHeight: CGFloat = 16
    private let labelGap: CGFloat = 8

    private var totalHeight: CGFloat {
        thumbSize + (showsLabels ? labelGap + labelHeight : 0)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - thumbSize, 1)          // 拇指中心可移动范围
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let thumbX = thumbSize / 2 + CGFloat(fraction) * usable
            let centerY = thumbSize / 2

            ZStack(alignment: .topLeading) {
                // 轨道
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: width, height: trackHeight)
                    .position(x: width / 2, y: centerY)

                // 已填充
                Capsule()
                    .fill(theme.accent)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)
                    .position(x: max(thumbX, trackHeight) / 2, y: centerY)

                // 档位刻度点
                ForEach(traps, id: \.self) { t in
                    Circle()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 3, height: 3)
                        .position(x: tickX(t, usable: usable), y: centerY)
                }

                // 拇指
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .position(x: thumbX, y: centerY)

                // 档位标签（与刻度点同一 x，故必然对齐；边缘标签自动夹紧避免溢出）
                if showsLabels {
                    ForEach(traps, id: \.self) { t in
                        Text(labelText(t))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize()
                            .alignmentGuide(.leading) { d in
                                let cx = tickX(t, usable: usable)
                                let left = min(max(cx - d.width / 2, 0), max(width - d.width, 0))
                                return -left
                            }
                            .alignmentGuide(.top) { _ in -(thumbSize + labelGap) }
                    }
                }
            }
            .frame(width: width, height: totalHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = Double((g.location.x - thumbSize / 2) / usable)
                        let raw = range.lowerBound + f * span
                        value = snapped(clampToRange(raw))
                    }
            )
        }
        .frame(height: totalHeight)
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
        }
    }

    private func tickX(_ t: Double, usable: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let f = span > 0 ? (t - range.lowerBound) / span : 0
        return thumbSize / 2 + CGFloat(f) * usable
    }

    /// 落在档位 snapRadius 范围内则吸附到该档位。
    private func snapped(_ v: Double) -> Double {
        for t in traps where abs(v - t) <= snapRadius { return t }
        return v
    }

    private func clampToRange(_ v: Double) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
