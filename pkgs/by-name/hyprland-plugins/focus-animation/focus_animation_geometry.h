#pragma once

namespace focus_animation {

    template <typename Position, typename Size>
    struct GeometryState {
        Position* position;
        Size*     size;
        bool      positionAnimated;
        bool      sizeAnimated;

        bool hasNativeAnimation() const noexcept {
            return positionAnimated || sizeAnimated;
        }

        bool hasInactiveVariable() const noexcept {
            return (position != nullptr && !positionAnimated) || (size != nullptr && !sizeAnimated);
        }

        void restoreInactive() const {
            if (position != nullptr && !positionAnimated)
                position->value() = position->goal();
            if (size != nullptr && !sizeAnimated)
                size->value() = size->goal();
        }
    };

    template <typename Position, typename Size>
    GeometryState<Position, Size> inspectGeometry(Position* position, Size* size) {
        return {
            .position          = position,
            .size              = size,
            .positionAnimated = position != nullptr && position->isBeingAnimated(),
            .sizeAnimated     = size != nullptr && size->isBeingAnimated(),
        };
    }

} // namespace focus_animation
