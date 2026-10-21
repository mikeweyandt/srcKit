#include <iostream>

int sum(int a, int b) {
    int total = a + b;
    return total;
}

int main() {
    int x = 3;
    int y = 5;
    int result = sum(x, y);
    std::cout << "sum: " << result << '\n';
    return 0;
}
