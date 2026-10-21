#include <iostream>

int sum(int a, int b) {
    int total = a + b;
    return total;
}

int main() {
    int x = 3;
    int y = 4;
    int result = sum(x, y);
    std::cout << result << '\n';
    return 0;
}
